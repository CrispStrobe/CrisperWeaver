#!/usr/bin/env bash
#
# Copy CrispASR's libwhisper.so + ggml shared libs into a built
# crisper_weaver Linux bundle so every backend the library was linked
# with is resolvable at runtime. Runs from either the local dev tree
# or CI after `flutter build linux`.
#
# Expects the sibling CrispASR repo at ../CrispASR (dev) or
# $CRISPASR_DIR (CI), with libwhisper.so already produced under
# $CRISPASR_DIR/$CRISPASR_BUILD_SUBDIR/src (default subdir: build).
#
# Per-backend .so files are NOT copied: every CrispASR backend
# (parakeet / canary / qwen3 / cohere / granite / voxtral / kokoro /
# vibevoice / qwen3_tts / fireredpunc / etc.) is built as a STATIC
# archive in src/CMakeLists.txt and pulled into libwhisper.so at
# link time. Bundling libwhisper.so alone is sufficient.
#
# Usage:
#   scripts/bundle_linux_libs.sh [path/to/bundle/dir]
# Env:
#   CRISPASR_DIR          path to sibling CrispASR repo (default: ../CrispASR)
#   CRISPASR_BUILD_SUBDIR cmake binary dir under CRISPASR_DIR (default: build)
#
# Default bundle path: build/linux/x64/{debug,release}/bundle

set -euo pipefail

BUNDLE="${1:-}"
if [[ -z "$BUNDLE" ]]; then
  for cfg in release debug profile; do
    candidate="build/linux/x64/$cfg/bundle"
    if [[ -d "$candidate" ]]; then BUNDLE="$candidate"; break; fi
  done
fi
if [[ -z "$BUNDLE" || ! -d "$BUNDLE" ]]; then
  echo "error: linux bundle dir not found. Run flutter build linux first, or pass the path explicitly." >&2
  exit 2
fi

CRISPASR_DIR="${CRISPASR_DIR:-$(cd "$(dirname "$0")/../.." && pwd)/CrispASR}"
CRISPASR_BUILD_SUBDIR="${CRISPASR_BUILD_SUBDIR:-build}"
SRCDIR="$CRISPASR_DIR/$CRISPASR_BUILD_SUBDIR/src"
GGMLDIR="$CRISPASR_DIR/$CRISPASR_BUILD_SUBDIR/ggml/src"

if [[ ! -d "$SRCDIR" ]]; then
  echo "error: CrispASR build tree not found at $SRCDIR" >&2
  echo "       Set CRISPASR_DIR / CRISPASR_BUILD_SUBDIR or build CrispASR first." >&2
  echo "       Tip: scripts/build_linux.sh runs the whole flow end-to-end." >&2
  exit 3
fi

LIBDIR="$BUNDLE/lib"
mkdir -p "$LIBDIR"

# Wipe any previous CrispASR bundle so stale per-backend .so files
# don't linger across rebuilds. Keep the Flutter-shipped lib*.so
# (libapp.so, libflutter_linux_gtk.so, etc.) — those have flutter_,
# app., or _plugin in their names, never libwhisper / libcrispasr /
# libggml / lib<backend>.
rm -f "$LIBDIR"/libwhisper*.so* "$LIBDIR"/libcrispasr*.so* "$LIBDIR"/libggml*.so* "$LIBDIR"/libglint.so*

# Core library. CrispASR produces libcrispasr.so.{version} plus
# symlinks libcrispasr.so and libwhisper.so; pick whichever concrete
# versioned file exists, falling back to the unversioned symlink.
VERSIONED=""
for pattern in 'libcrispasr.so.*' 'libwhisper.so.*'; do
  found="$(find "$SRCDIR" -maxdepth 1 -type f -name "$pattern" 2>/dev/null | sort | head -1)"
  if [[ -n "$found" ]]; then VERSIONED="$found"; break; fi
done
if [[ -z "$VERSIONED" ]]; then
  for cand in "$SRCDIR/libcrispasr.so" "$SRCDIR/libwhisper.so"; do
    if [[ -f "$cand" || -L "$cand" ]]; then VERSIONED="$cand"; break; fi
  done
fi
if [[ -z "$VERSIONED" ]]; then
  echo "error: libcrispasr / libwhisper .so not found under $SRCDIR" >&2
  exit 4
fi
cp -L "$VERSIONED" "$LIBDIR/libwhisper.so"
# Aliases so:
#   * Dart's preferred name (libcrispasr.so) resolves
#   * libwhisper.so's own SONAME (typically libcrispasr.so.1) resolves
#     on dlopen — otherwise the loader fails with
#     "libcrispasr.so.1: cannot open shared object file" even though
#     the file IS the lib it points at.
ln -sf libwhisper.so "$LIBDIR/libcrispasr.so"
ln -sf libwhisper.so "$LIBDIR/libcrispasr.so.1"

# Bundle every ggml shared library (incl. version aliases).
if [[ -d "$GGMLDIR" ]]; then
  find "$GGMLDIR" -name "libggml*.so*" -exec cp -P {} "$LIBDIR/" \;
fi

# glint codec library (on-device MP3 / AAC-LC / Opus). Self-contained
# (only libc/libm/libstdc++), so a plain copy into the bundle's lib/ dir
# resolves it like libwhisper ($ORIGIN/lib is on the rpath). Non-fatal —
# the app falls back to WAV/ffmpeg at runtime when it's absent.
GLINT_DIR="${GLINT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)/glint}"
GLINT_SO=""
for cand in "$GLINT_DIR/build/libglint.so" "$GLINT_DIR/build-fixed/libglint.so"; do
  if [[ -f "$cand" ]]; then GLINT_SO="$cand"; break; fi
done
if [[ -n "$GLINT_SO" ]]; then
  cp -L "$GLINT_SO" "$LIBDIR/libglint.so"
  echo "Bundled libglint from $GLINT_SO"
else
  echo "warn: libglint.so not found under $GLINT_DIR; MP3/AAC/Opus codec disabled (app falls back to WAV/ffmpeg)" >&2
fi

echo "Bundled .so files:"
ls -l "$LIBDIR" | grep -E "\.so" | awk '{print "  " $NF}'

# Report which backends made it into libwhisper.so, parsed from its
# exported <backend>_init symbols. Same source of truth the
# CrispasrSession.availableBackends() FFI call uses at runtime.
if command -v nm >/dev/null 2>&1; then
  echo
  echo "Backends linked into libwhisper.so:"
  nm -D --defined-only "$LIBDIR/libwhisper.so" 2>/dev/null \
    | awk '{print $3}' \
    | grep -oE '(canary(_ctc)?|cohere|parakeet|qwen3_asr|qwen3_tts|granite_speech|voxtral4?b?|wav2vec2|kokoro|orpheus|vibevoice|moonshine(_streaming)?|omniasr|firered_(asr|vad|lid)|fireredpunc|glm_asr|kyutai_stt|mimo_(asr|tokenizer)|gemma4_e2b|silero_lid|ecapa_lid|marblenet_vad|pyannote_seg)_init(_from_file|_with_params)?$' \
    | sort -u \
    | sed -E 's/^/  /; s/_init(_from_file|_with_params)?$//' || true
fi
