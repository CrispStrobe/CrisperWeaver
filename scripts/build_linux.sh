#!/usr/bin/env bash
#
# End-to-end Linux build:
#   1. (re)configure + build CrispASR's libwhisper.so with every
#      backend (ASR + TTS + post-processors) statically linked in
#   2. flutter build linux
#   3. bundle libwhisper.so + ggml .so files into the Flutter bundle's
#      lib/ directory via bundle_linux_libs.sh
#
# Usage:
#   scripts/build_linux.sh [debug|release] [--rebuild-cmake]
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
# for a different purpose. Using a CrisperWeaver-specific subdir keeps
# our build options from fighting whatever else is in the same checkout.

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
    -DCRISPASR_BUILD_TESTS=OFF \
    -DCRISPASR_BUILD_EXAMPLES=OFF \
    -DCRISPASR_BUILD_SERVER=OFF \
    -DCRISPASR_OPUS_FETCH=ON
fi

# ---------------------------------------------------------------------------
# Step 2: build every backend STATIC archive plus the shared crispasr
# (libwhisper.so). Same dependency-graph ordering as the macOS flow.
# ---------------------------------------------------------------------------
JOBS_FLAG=""
if [[ -n "${JOBS:-}" ]]; then JOBS_FLAG="-j $JOBS"; else JOBS_FLAG="--parallel"; fi

BACKEND_TARGETS=(
  # ASR
  parakeet canary canary_ctc qwen3_asr cohere granite_speech granite_nle
  voxtral voxtral4b wav2vec2-ggml glm-asr kyutai-stt firered-asr
  funasr paraformer sensevoice omniasr
  moonshine moonshine_streaming gemma4_e2b mimo_tokenizer mimo_asr vibevoice
  moss_audio
  # TTS
  qwen3_tts orpheus chatterbox indextts kokoro piper-tts
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

echo "==> link libwhisper.so"
cmake --build "$BUILDDIR" $JOBS_FLAG --target crispasr-lib 2>&1 \
  | grep -E "(Built target|Linking|error:|Error)" || true

LIBPATH="$BUILDDIR/src/libwhisper.so"
if [[ ! -f "$LIBPATH" && ! -L "$LIBPATH" ]]; then
  # CMake on Linux usually drops the unversioned symlink — but if it
  # only produced libcrispasr.so or a versioned name, that's fine.
  LIBPATH="$(find "$BUILDDIR/src" -maxdepth 1 -name 'libwhisper.so*' -o -name 'libcrispasr.so*' 2>/dev/null | head -1)"
  if [[ -z "$LIBPATH" ]]; then
    echo "error: libwhisper.so / libcrispasr.so not produced under $BUILDDIR/src" >&2
    exit 4
  fi
fi

# ---------------------------------------------------------------------------
# Step 2b: verify native library capabilities
# ---------------------------------------------------------------------------
echo "==> verify libcrispasr capabilities"
_verify_sym() {
  if ! nm -D "$LIBPATH" 2>/dev/null | grep -q "$1"; then
    echo "WARNING: $LIBPATH missing symbol: $1" >&2
    return 1
  fi
}
_verify_sym crispasr_audio_load || true
_verify_sym whisper_full || true
# Opus decode — if missing, .opus files won't decode natively.
if _verify_sym opus_decode_float && _verify_sym op_open_file; then
  echo "  ✓ opus decode symbols present"
else
  echo "  ⚠ opus decode symbols missing (CRISPASR_OPUS_FETCH=ON may not have worked)"
fi

# ---------------------------------------------------------------------------
# Step 3: flutter build
# ---------------------------------------------------------------------------
cd "$REPO_ROOT"
echo "==> flutter pub get"
flutter pub get >/dev/null

echo "==> flutter build linux $FLUTTER_FLAG"
flutter build linux $FLUTTER_FLAG

# Resolve the resulting bundle path. Linux flutter build always lands
# in build/linux/x64/{debug,release,profile}/bundle.
BUNDLE_CFG="debug"
if [[ "$CONFIG" == "release" || "$CONFIG" == "Release" ]]; then BUNDLE_CFG="release"; fi
BUNDLE="$REPO_ROOT/build/linux/x64/$BUNDLE_CFG/bundle"
if [[ ! -d "$BUNDLE" ]]; then
  echo "error: expected bundle not found at $BUNDLE" >&2
  exit 5
fi

# ---------------------------------------------------------------------------
# Step 4: bundle .so files into the Flutter bundle's lib/ directory
# ---------------------------------------------------------------------------
echo "==> bundle .so files"
CRISPASR_DIR="$CRISPASR_DIR" CRISPASR_BUILD_SUBDIR="$CRISPASR_BUILD_SUBDIR" \
  "$REPO_ROOT/scripts/bundle_linux_libs.sh" "$BUNDLE"

EXE="$BUNDLE/crisper_weaver"
echo
echo "==> done: $EXE"
echo "    Run it with:  '$EXE'"
