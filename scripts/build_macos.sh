#!/usr/bin/env bash
#
# End-to-end macOS build:
#   1. (re)configure + build CrispASR's libwhisper.dylib with every
#      backend (ASR + TTS + post-processors) statically linked in
#   2. flutter build macos
#   3. bundle libwhisper.dylib + ggml dylibs into the .app
#
# Usage:
#   scripts/build_macos.sh [debug|release] [--rebuild-cmake]
#
# Env:
#   CRISPASR_DIR          path to sibling CrispASR repo
#                         (default: ../CrispASR)
#   CRISPASR_BUILD_SUBDIR cmake binary dir under CRISPASR_DIR
#                         (default: build-flutter-bundle)
#   JOBS                  parallel build jobs (default: cmake's choice)
#
# The default subdir is "build-flutter-bundle" rather than "build" on
# purpose: the upstream CrispASR repo's `build/` is often configured
# for a different purpose (server, examples, sanitizer, etc.). Using a
# CrisperWeaver-specific subdir means our build options don't fight
# whatever else is in the same checkout.

set -euo pipefail

CONFIG="${1:-debug}"
case "$CONFIG" in
  debug|Debug) FLUTTER_FLAG=--debug; CMAKE_BUILD_TYPE=Release ;;
  release|Release) FLUTTER_FLAG=--release; CMAKE_BUILD_TYPE=Release ;;
  *) echo "usage: $0 [debug|release] [--rebuild-cmake]" >&2; exit 2 ;;
esac
shift || true
REBUILD_CMAKE=0
for arg in "$@"; do
  if [[ "$arg" == "--rebuild-cmake" ]]; then REBUILD_CMAKE=1; fi
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CRISPASR_DIR="${CRISPASR_DIR:-$(cd "$REPO_ROOT/.." && pwd)/CrispASR}"
CRISPASR_BUILD_SUBDIR="${CRISPASR_BUILD_SUBDIR:-build-flutter-bundle}"
BUILDDIR="$CRISPASR_DIR/$CRISPASR_BUILD_SUBDIR"

if [[ ! -d "$CRISPASR_DIR" ]]; then
  echo "error: sibling CrispASR repo not at $CRISPASR_DIR" >&2
  echo "       Clone it: git clone https://github.com/CrispStrobe/CrispASR \"$CRISPASR_DIR\"" >&2
  exit 3
fi

CRISPEMBED_DIR="${CRISPEMBED_DIR:-$(cd "$REPO_ROOT/.." && pwd)/CrispEmbed}"
if [[ ! -d "$CRISPEMBED_DIR" ]]; then
  echo "error: sibling CrispEmbed repo not at $CRISPEMBED_DIR" >&2
  echo "       Clone it: git clone https://github.com/CrispStrobe/CrispEmbed \"$CRISPEMBED_DIR\"" >&2
  exit 3
fi

echo "==> CrispASR repo:    $CRISPASR_DIR"
echo "==> CrispASR build:   $BUILDDIR"
echo "==> Flutter config:   $CONFIG"

# ---------------------------------------------------------------------------
# Step 1: configure CrispASR (skip if cmake cache already exists, unless
# --rebuild-cmake is passed)
# ---------------------------------------------------------------------------
if [[ $REBUILD_CMAKE == 1 || ! -f "$BUILDDIR/CMakeCache.txt" ]]; then
  echo "==> cmake configure"
  rm -rf "$BUILDDIR"
  cmake -S "$CRISPASR_DIR" -B "$BUILDDIR" \
    -DCMAKE_BUILD_TYPE=$CMAKE_BUILD_TYPE \
    -DBUILD_SHARED_LIBS=ON \
    -DGGML_METAL=ON \
    -DCRISPASR_COREML=ON \
    -DCRISPASR_COREML_ALLOW_FALLBACK=ON \
    -DCRISPASR_BUILD_TESTS=OFF \
    -DCRISPASR_BUILD_EXAMPLES=OFF \
    -DCRISPASR_BUILD_SERVER=OFF \
    -DCRISPASR_OPUS_FETCH=ON
fi
# CRISPASR_COREML=ON wires Apple's CoreML encoder into libwhisper. When
# whisper opens a ggml-MODEL.bin file, it probes for a sibling
# ggml-MODEL-encoder.mlmodelc directory and uses it (Apple Neural
# Engine, 2-3× faster on whisper-large) instead of the ggml encoder.
# CRISPASR_COREML_ALLOW_FALLBACK=ON means missing .mlmodelc files don't
# error — the model just runs the slower path. Companion .mlmodelc
# bundles are auto-fetched by ModelService.downloadWhisperCppModel
# when the matching ggml-*.bin is downloaded.

# ---------------------------------------------------------------------------
# Step 2: build every backend STATIC archive plus the shared crispasr
# (libwhisper.dylib).
#
# CMake's "build target X" only pulls in dependencies declared via
# target_link_libraries. The per-backend libs are linked into crispasr-lib
# via `if (TARGET <name>) target_link_libraries(crispasr-lib PUBLIC <name>)`,
# which is a runtime check on the dependency graph — not a hard link
# the way `target_link_libraries(... PUBLIC ggml)` would be. So we have
# to ask cmake to build the static archives FIRST, then re-link
# crispasr so its DT_NEEDED edges pick them up.
# ---------------------------------------------------------------------------
JOBS_FLAG=""
if [[ -n "${JOBS:-}" ]]; then JOBS_FLAG="-j $JOBS"; else JOBS_FLAG="--parallel"; fi

# Backends that ship in CrispASR today, mapped 1:1 to add_library(...) targets
# in src/CMakeLists.txt. The crispasr-lib link step auto-pulls deps, but
# listing them here ensures build errors surface early.
BACKEND_TARGETS=(
  # ASR
  parakeet canary canary_ctc qwen3_asr cohere granite_speech granite_nle
  voxtral voxtral4b wav2vec2-ggml glm-asr kyutai-stt firered-asr
  funasr paraformer sensevoice omniasr
  moonshine moonshine_streaming gemma4_e2b mimo_tokenizer mimo_asr vibevoice
  moss_audio moss_transcribe_diarize
  # TTS
  qwen3_tts moss_tts orpheus chatterbox indextts kokoro piper-tts
  voxcpm2_tts cosyvoice3_tts f5-tts outetts
  bark-tts csm-tts dia-tts fastpitch-tts parler-tts speecht5-tts
  pocket-tts zonos-tts melotts bert-encoder openvoice2 kugelaudio
  # Translation
  m2m100 t5_translate
  # Post-processing & LID
  fireredpunc pcs truecaser truecaser_crf truecaser_lstm
  pyannote-seg silero-lid ecapa-lid firered-lid firered-vad marblenet-vad
  crispasr-vad-encdec titanet ctc-align
  lid-cld3 lid-fasttext text-lid-dispatch
)

echo "==> build backend statics (${#BACKEND_TARGETS[@]} targets)"
cmake --build "$BUILDDIR" $JOBS_FLAG --target "${BACKEND_TARGETS[@]}" 2>&1 \
  | grep -E "(Built target|error:|Error)" || true

echo "==> link libwhisper.dylib"
cmake --build "$BUILDDIR" $JOBS_FLAG --target crispasr-lib 2>&1 \
  | grep -E "(Built target|Linking|error:|Error)" || true

# Sanity: at least the basic ASR backends should be linked in. If not,
# the cmake config probably picked up a slim build path.
LIBPATH="$BUILDDIR/src/libwhisper.dylib"
if [[ ! -f "$LIBPATH" && ! -L "$LIBPATH" ]]; then
  echo "error: libwhisper.dylib not produced at $LIBPATH" >&2
  exit 4
fi

# ---------------------------------------------------------------------------
# Step 2b: verify native library capabilities
# ---------------------------------------------------------------------------
echo "==> verify libwhisper capabilities"
_verify_sym() {
  if ! nm -gU "$LIBPATH" 2>/dev/null | grep -q "$1"; then
    echo "WARNING: $LIBPATH missing symbol: $1" >&2
    return 1
  fi
}
_verify_sym _crispasr_audio_load || true
_verify_sym _whisper_full || true
# Opus decode — if missing, .opus files won't decode natively.
if _verify_sym _opus_decode_float && _verify_sym _op_open_file; then
  echo "  ✓ opus decode symbols present"
else
  echo "  ⚠ opus decode symbols missing (CRISPASR_OPUS_FETCH=ON may not have worked)"
fi

# ---------------------------------------------------------------------------
# Step 2c: build the glint codec library (libglint.dylib) for the app's
# on-device MP3 / AAC-LC / Opus encode + decode. glint is self-contained
# (no external deps), so a plain Release cmake build is all it needs.
# Non-fatal: without it the app falls back to WAV/ffmpeg.
# ---------------------------------------------------------------------------
GLINT_DIR="${GLINT_DIR:-$(cd "$REPO_ROOT/.." && pwd)/glint}"
if [[ -d "$GLINT_DIR" ]]; then
  echo "==> build libglint.dylib"
  GLINT_BUILD="$GLINT_DIR/build"
  if [[ $REBUILD_CMAKE == 1 || ! -f "$GLINT_BUILD/CMakeCache.txt" ]]; then
    cmake -S "$GLINT_DIR" -B "$GLINT_BUILD" -DCMAKE_BUILD_TYPE=Release >/dev/null
  fi
  cmake --build "$GLINT_BUILD" $JOBS_FLAG --target glint_shared 2>&1 \
    | grep -E "(Built target|Linking|error:|Error)" || true
  if [[ -f "$GLINT_BUILD/libglint.dylib" ]]; then
    echo "  ✓ libglint.dylib built"
  else
    echo "  ⚠ libglint.dylib not produced; app falls back to WAV/ffmpeg" >&2
  fi
else
  echo "warn: sibling glint repo not at $GLINT_DIR — skipping codec lib (app falls back to WAV/ffmpeg)" >&2
fi

# ---------------------------------------------------------------------------
# Step 3: flutter build
# ---------------------------------------------------------------------------
cd "$REPO_ROOT"
echo "==> flutter pub get"
flutter pub get >/dev/null

echo "==> flutter build macos $FLUTTER_FLAG"
# CocoaPods runs under Homebrew ruby, but a chruby line in ~/.zshrc
# exports GEM_PATH/GEM_HOME for a DIFFERENT ruby. pod then dies with
# "Could not find 'nkf'", flutter reports "CocoaPods not installed or
# not in valid state", skips pod install, and produces no .app at all.
# Harmless on CI, where neither var is set.
unset GEM_PATH GEM_HOME
flutter build macos $FLUTTER_FLAG 2>&1 \
  | grep -vE "(Run script build phase|Metal\.xctoolchain)" || true

# Resolve the resulting .app path. macOS build always lands in
# Build/Products/{Debug,Release,Profile}/.
APPCFG="Debug"
if [[ "$CONFIG" == "release" || "$CONFIG" == "Release" ]]; then APPCFG="Release"; fi
APP="$REPO_ROOT/build/macos/Build/Products/$APPCFG/crisper_weaver.app"
if [[ ! -d "$APP" ]]; then
  echo "error: expected .app not found at $APP" >&2
  exit 5
fi

# ---------------------------------------------------------------------------
# Step 4: bundle dylibs
# ---------------------------------------------------------------------------
echo "==> bundle dylibs"
CRISPASR_DIR="$CRISPASR_DIR" CRISPASR_BUILD_SUBDIR="$CRISPASR_BUILD_SUBDIR" \
  GLINT_DIR="$GLINT_DIR" \
  "$REPO_ROOT/scripts/bundle_macos_dylibs.sh" "$APP"

echo
echo "==> done: $APP"
echo "    Open it with:  open '$APP'"
