#!/usr/bin/env bash
#
# Copy CrispASR's libwhisper.dylib + ggml shared libs into a built
# crisper_weaver.app bundle so every backend the library was linked
# with is resolvable at runtime. Runs from either the local dev tree
# or CI after `flutter build macos`.
#
# Expects the sibling CrispASR repo at ../CrispASR (dev) or
# $CRISPASR_DIR (CI), with libwhisper.dylib already produced under
# $CRISPASR_DIR/$CRISPASR_BUILD_SUBDIR/src (default subdir: build).
#
# Per-backend dylibs are NOT copied: every CrispASR backend
# (parakeet / canary / qwen3 / cohere / granite / voxtral / kokoro /
# vibevoice / qwen3_tts / fireredpunc / etc.) is built as a STATIC
# archive in src/CMakeLists.txt and pulled into libwhisper.dylib at
# link time. Bundling libwhisper.dylib alone is sufficient.
#
# Usage:
#   scripts/bundle_macos_dylibs.sh [path/to/.app]
# Env:
#   CRISPASR_DIR          path to sibling CrispASR repo (default: ../CrispASR)
#   CRISPASR_BUILD_SUBDIR cmake binary dir under CRISPASR_DIR (default: build)
#
# Default app path: build/macos/Build/Products/{Debug,Release}/crisper_weaver.app

set -euo pipefail

APP="${1:-${APP:-}}"
if [[ -z "$APP" ]]; then
  for cfg in Debug Release Profile; do
    candidate="build/macos/Build/Products/$cfg/crisper_weaver.app"
    if [[ -d "$candidate" ]]; then APP="$candidate"; break; fi
  done
fi
if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "error: app bundle not found. Run flutter build macos first, or pass the path explicitly." >&2
  exit 2
fi

CRISPASR_DIR="${CRISPASR_DIR:-$(cd "$(dirname "$0")/../.." && pwd)/CrispASR}"
CRISPASR_BUILD_SUBDIR="${CRISPASR_BUILD_SUBDIR:-build}"
SRCDIR="$CRISPASR_DIR/$CRISPASR_BUILD_SUBDIR/src"
GGMLDIR="$CRISPASR_DIR/$CRISPASR_BUILD_SUBDIR/ggml/src"

if [[ ! -d "$SRCDIR" ]]; then
  echo "error: CrispASR build tree not found at $SRCDIR" >&2
  echo "       Set CRISPASR_DIR / CRISPASR_BUILD_SUBDIR or build CrispASR first." >&2
  echo "       Tip: scripts/build_macos.sh runs the whole flow end-to-end." >&2
  exit 3
fi

FRAMEWORKS="$APP/Contents/Frameworks"
mkdir -p "$FRAMEWORKS"

# Wipe any previous bundle so stale per-backend dylibs from the old
# `cp lib<backend>.dylib …` loop don't linger across rebuilds.
#
# ONLY the libraries this script owns — a blanket `rm -f lib*.dylib` also
# deleted the dylibs CocoaPods had just embedded for the crispembed pod
# (Pods-Runner-frameworks.sh copies libcrispembed.0.dylib + its ggml
# siblings into Frameworks during `flutter build macos`, and the pod's
# OTHER_LDFLAGS `-lcrispembed.0` makes the Runner binary HARD-LINK it).
# Nothing put libcrispembed back afterwards, so every shipped .app since
# CrispEmbed started vendoring real macOS dylibs died at launch with
# "Library not loaded: @rpath/libcrispembed.0.dylib" before main() ran
# (issue #32, v0.9.8). Mirrors bundle_linux_libs.sh, which was always
# targeted. The trailing verify_dyld_closure() below is the real guard.
rm -f "$FRAMEWORKS"/libwhisper*.dylib \
      "$FRAMEWORKS"/libcrispasr*.dylib \
      "$FRAMEWORKS"/libggml*.dylib \
      "$FRAMEWORKS"/libglint*.dylib

# Core library. CrispASR produces libcrispasr.{version}.dylib plus
# symlinks libcrispasr.dylib and libwhisper.dylib; pick the highest-
# version concrete file (`sort -V | tail -1`), not the first alphabetic
# match — without that, when 0.5.4 + 0.6.6 coexist in the build dir
# we'd pick 0.5.4 because "0.5" sorts before "0.6", shipping the app
# with a stale ABI that's missing kokoro/TTS backends and produces
# NaN PCM at synth time. Use find so an unmatched glob doesn't break
# under `set -u`.
VERSIONED=""
for pattern in 'libcrispasr.[0-9]*.dylib' 'libwhisper.[0-9]*.dylib'; do
  found="$(find "$SRCDIR" -maxdepth 1 -type f -name "$pattern" 2>/dev/null | sort -V | tail -1)"
  if [[ -n "$found" ]]; then VERSIONED="$found"; break; fi
done
if [[ -z "$VERSIONED" ]]; then
  for cand in "$SRCDIR/libcrispasr.dylib" "$SRCDIR/libwhisper.dylib"; do
    if [[ -f "$cand" || -L "$cand" ]]; then VERSIONED="$cand"; break; fi
  done
fi
if [[ -z "$VERSIONED" ]]; then
  echo "error: libcrispasr / libwhisper dylib not found under $SRCDIR" >&2
  exit 4
fi
cp -L "$VERSIONED" "$FRAMEWORKS/libwhisper.dylib"
# Aliases so:
#   * Dart's preferred name (libcrispasr.dylib) resolves
#   * libwhisper.dylib's own SONAME (LC_ID_DYLIB → @rpath/libcrispasr.1.dylib)
#     resolves on dlopen; otherwise the loader reports
#     "Library not loaded: @rpath/libcrispasr.1.dylib" even though the
#     file IS the lib it's pointing at. The unversioned major-only alias
#     covers anyone consuming the SOVERSION-1 ABI.
ln -sf libwhisper.dylib "$FRAMEWORKS/libcrispasr.dylib"
ln -sf libwhisper.dylib "$FRAMEWORKS/libcrispasr.1.dylib"

# Bundle Homebrew dependencies that libwhisper picked up via absolute
# paths so the .app runs on machines without that brew package
# installed (kokoro pulls in espeak-ng for in-process phonemisation).
# Each external dep gets copied next to libwhisper, then the install
# name in libwhisper is rewritten to @rpath/<basename> so dyld finds
# the bundled copy first.
external_deps() {
  otool -L "$FRAMEWORKS/libwhisper.dylib" 2>/dev/null \
    | awk 'NR>1 {print $1}' \
    | grep -E '^/(opt/homebrew|usr/local)/' || true
}
for dep in $(external_deps); do
  base="$(basename "$dep")"
  if [[ -f "$dep" && ! -f "$FRAMEWORKS/$base" ]]; then
    cp -L "$dep" "$FRAMEWORKS/$base"
  fi
  install_name_tool -change "$dep" "@rpath/$base" \
    "$FRAMEWORKS/libwhisper.dylib" 2>/dev/null || true
done

# Bundle every ggml shared library (incl. version aliases).
#
# ONE ggml for the whole bundle: libcrispembed.0.dylib was built against
# ggml 0.10.2 and CrispASR ships 0.17.0, but both reference the same
# @rpath/libggml*.0.dylib install names, so the two sets cannot coexist in
# a flat Frameworks/ — CrispASR's wins and crispembed binds to it. Checked
# at the symbol level: all 144 ggml imports of libcrispembed resolve
# against the 0.17.0 set. Android/iOS sidestep this entirely (crispembed
# links ggml statically there).
if [[ -d "$GGMLDIR" ]]; then
  find "$GGMLDIR" -name "libggml*.dylib" -exec cp -R {} "$FRAMEWORKS/" \;
fi

# CrispEmbed (semantic transcript search + math OCR). Normally CocoaPods
# has already embedded it and the targeted wipe above leaves it alone;
# this restores it when the bundler runs against an .app built by some
# other path (or an older one whose copy the blanket wipe ate). Only the
# crispembed dylib itself — its ggml siblings are deliberately dropped in
# favour of CrispASR's set, per the note above.
if ! ls "$FRAMEWORKS"/libcrispembed*.dylib >/dev/null 2>&1; then
  REPO_ROOT_EARLY="$(cd "$(dirname "$0")/.." && pwd)"
  CRISPEMBED_LIBS=""
  for cand in \
    "$REPO_ROOT_EARLY/macos/Flutter/ephemeral/.symlinks/plugins/crispembed/macos/Libs" \
    "${CRISPEMBED_DIR:-$(cd "$(dirname "$0")/../.." && pwd)/CrispEmbed}/flutter/crispembed/macos/Libs"; do
    if ls "$cand"/libcrispembed*.dylib >/dev/null 2>&1; then CRISPEMBED_LIBS="$cand"; break; fi
  done
  if [[ -n "$CRISPEMBED_LIBS" ]]; then
    find "$CRISPEMBED_LIBS" -maxdepth 1 -name "libcrispembed*.dylib" \
      -exec cp -L {} "$FRAMEWORKS/" \;
    echo "Restored libcrispembed from $CRISPEMBED_LIBS"
  else
    echo "warn: libcrispembed*.dylib missing from the bundle and no source found;" >&2
    echo "      the app links it at load time and WILL abort at launch." >&2
  fi
fi

# glint codec library (on-device MP3 / AAC-LC / Opus encode + decode).
# Self-contained (only links system libc++/libSystem) and its install id
# is already @rpath/libglint.dylib, so a plain copy into Frameworks
# resolves the same way libcrispasr does. Non-fatal if absent — the app
# falls back to WAV/ffmpeg at runtime (GlintCodecService.isAvailable
# gates on whether this loaded). Build it with:
#   cmake -B build -DCMAKE_BUILD_TYPE=Release ../glint && cmake --build build
GLINT_DIR="${GLINT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)/glint}"
GLINT_DYLIB=""
for cand in \
  "$GLINT_DIR/build/libglint.dylib" \
  "$GLINT_DIR/build-fixed/libglint.dylib"; do
  if [[ -f "$cand" ]]; then GLINT_DYLIB="$cand"; break; fi
done
if [[ -n "$GLINT_DYLIB" ]]; then
  cp -L "$GLINT_DYLIB" "$FRAMEWORKS/libglint.dylib"
  install_name_tool -id @rpath/libglint.dylib "$FRAMEWORKS/libglint.dylib" 2>/dev/null || true
  echo "Bundled libglint from $GLINT_DYLIB"
else
  echo "warn: libglint.dylib not found under $GLINT_DIR; MP3/AAC/Opus codec disabled (app falls back to WAV/ffmpeg)" >&2
fi

# espeak-ng (GPL-3.0) is deliberately NOT bundled — CrispASR is built
# WITH_ESPEAK_NG=AUTO (dlopen at runtime, not linked), so libwhisper carries
# no espeak dependency and kokoro/piper use the built-in non-GPL G2P
# (EN/DE/FR/ES). Keeps the .app MIT/BSD-only for the Mac App Store. A user
# who wants espeak can install it (brew) or drop libespeak-ng + espeak-ng-data
# in themselves; the runtime dlopen picks it up.

# Verify the bundle's dyld closure BEFORE signing: every @rpath/… load
# command of every Mach-O in the bundle (plus each dylib's own LC_ID_DYLIB
# name, which dyld matches against on dlopen) must exist under Frameworks/.
# All the app's rpaths — @executable_path/../Frameworks for the Runner,
# @loader_path/../Frameworks for the pods — land there.
#
# This is the gate that was missing: nothing in CI ever launched the .app,
# so a bundle with a deleted libcrispembed.0.dylib shipped as v0.9.8 and
# SIGABRT'd at launch on every user's machine (#32). A missing @rpath dep
# is always fatal at load time, so failing the build here is right.
verify_dyld_closure() {
  local app="$1"
  local fw="$app/Contents/Frameworks"
  local missing=0 checked=0 bin dep base

  while IFS= read -r -d '' bin; do
    case "$(file -b "$bin" 2>/dev/null)" in *Mach-O*) ;; *) continue ;; esac
    checked=$((checked + 1))
    while read -r dep; do
      case "$dep" in
        # Swift runtime lives in the OS (/usr/lib/swift) since 10.14.4 and is
        # only embedded on older targets; not ours to bundle.
        @rpath/libswift*) continue ;;
        @rpath/*) base="${dep#@rpath/}" ;;
        *) continue ;;
      esac
      if [[ ! -e "$fw/$base" ]]; then
        echo "  MISSING: $base   (needed by ${bin#"$app/"})" >&2
        missing=$((missing + 1))
      fi
    done < <(otool -L "$bin" 2>/dev/null | awk 'NR>1 {print $1}')
  done < <(find "$app/Contents" -type f -print0)

  if [[ $missing -gt 0 ]]; then
    echo "error: $missing unresolved @rpath dependency/dependencies in $app" >&2
    echo "       The app would abort at launch (dyld: Library not loaded)." >&2
    return 1
  fi
  echo "dyld closure OK ($checked Mach-O files, all @rpath deps resolve)"
}
verify_dyld_closure "$APP"

# Ad-hoc codesign so Gatekeeper accepts the modified bundle locally.
# Release builds should re-sign with a real Developer ID via codesign
# separately.
#
# Preserve the entitlements baked in by `flutter build macos` —
# without `--entitlements`, `codesign --force` strips them, leaving
# the .app without `com.apple.security.files.user-selected.read-write`
# etc., and the file_picker plugin then throws
# `PlatformException(ENTITLEMENT_NOT_FOUND, …)` at runtime.
#
# Read the entitlements straight from the source plist in
# macos/Runner/ rather than `codesign -d --entitlements -`: that
# command emits a binary `kSecCodeSignerEntitlements` blob (with
# 8-byte magic header), not a plist, so re-feeding it to
# `codesign --entitlements` warns "unrecognized blob type" and
# fails on CI. Choosing Debug vs Release from the .app path keeps
# Release builds clean of hot-reload-only entries.
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
case "$APP" in
  *"/Release/"*) ENT_SRC="$REPO_ROOT/macos/Runner/Release.entitlements" ;;
  *)             ENT_SRC="$REPO_ROOT/macos/Runner/DebugProfile.entitlements" ;;
esac
if [[ -f "$ENT_SRC" ]]; then
  codesign --force --deep --sign - --entitlements "$ENT_SRC" "$APP" >/dev/null
else
  echo "warn: entitlements source $ENT_SRC missing, signing without" >&2
  codesign --force --deep --sign - "$APP" >/dev/null
fi

echo "Bundled dylibs:"
ls -l "$FRAMEWORKS" | grep -E "\.dylib" | awk '{print "  " $NF}'

# Report which backends made it into libwhisper.dylib, parsed from its
# exported _<backend>_init symbols. Same source of truth the
# CrispasrSession.availableBackends() FFI call uses at runtime.
if command -v nm >/dev/null 2>&1; then
  echo
  echo "Backends linked into libwhisper.dylib:"
  nm -gU "$FRAMEWORKS/libwhisper.dylib" 2>/dev/null \
    | awk '{print $3}' \
    | grep -oE '_(canary(_ctc)?|cohere|parakeet|qwen3_asr|qwen3_tts|granite_speech|voxtral4?b?|wav2vec2|kokoro|orpheus|vibevoice|moonshine(_streaming)?|omniasr|firered_(asr|vad|lid)|fireredpunc|glm_asr|kyutai_stt|mimo_(asr|tokenizer)|gemma4_e2b|silero_lid|ecapa_lid|marblenet_vad|pyannote_seg)_init(_from_file|_with_params)?$' \
    | sort -u \
    | sed 's/^_/  /' \
    | sed -E 's/_init(_from_file|_with_params)?$//' || true
fi
