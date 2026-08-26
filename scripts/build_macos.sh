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
#   CRISPASR_BUILD_DIR    absolute CMake binary dir override (useful when the
#                         source volume is short on space)
#   CRISPEMBED_BUILD_DIR  absolute CrispEmbed CMake binary dir override
#   GLINT_BUILD_DIR       absolute glint CMake binary dir override
#   JOBS                  parallel build jobs (default: min(2, logical CPUs))
#   BUILD_LOAD_MAX        maximum 1-minute load before a large compile starts
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
BUILDDIR="${CRISPASR_BUILD_DIR:-$CRISPASR_DIR/$CRISPASR_BUILD_SUBDIR}"

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
CRISPEMBED_BUILD="${CRISPEMBED_BUILD_DIR:-$CRISPEMBED_DIR/build-crisperweaver}"

echo "==> CrispASR repo:    $CRISPASR_DIR"
echo "==> CrispASR build:   $BUILDDIR"
echo "==> CrispEmbed build: $CRISPEMBED_BUILD"
echo "==> Flutter config:   $CONFIG"

# Do not pile a native build onto an already busy workstation. Re-check before
# both expensive CrispASR phases because another build may start meanwhile.
"$REPO_ROOT/scripts/check_build_load.sh"

# ---------------------------------------------------------------------------
# Step 1: configure CrispASR (skip if cmake cache already exists, unless
# --rebuild-cmake is passed)
# ---------------------------------------------------------------------------
NEED_CMAKE_CONFIGURE=0
if [[ $REBUILD_CMAKE == 1 || ! -f "$BUILDDIR/CMakeCache.txt" ]]; then
  NEED_CMAKE_CONFIGURE=1
else
  CACHED_DEPLOYMENT=$(sed -n 's/^CMAKE_OSX_DEPLOYMENT_TARGET:STRING=//p' "$BUILDDIR/CMakeCache.txt" | head -1)
  CACHED_ARCHS=$(sed -n 's/^CMAKE_OSX_ARCHITECTURES:STRING=//p' "$BUILDDIR/CMakeCache.txt" | head -1)
  if [[ "$CACHED_DEPLOYMENT" != "13.3" || "$CACHED_ARCHS" != "arm64" ]]; then
    echo "==> cmake cache compatibility changed (${CACHED_DEPLOYMENT:-unset}/${CACHED_ARCHS:-unset} -> 13.3/arm64)"
    NEED_CMAKE_CONFIGURE=1
  fi
fi
if [[ $NEED_CMAKE_CONFIGURE == 1 ]]; then
  echo "==> cmake configure"
  if [[ $REBUILD_CMAKE == 1 ]]; then rm -rf "$BUILDDIR"; fi
  cmake -S "$CRISPASR_DIR" -B "$BUILDDIR" \
    -DCMAKE_BUILD_TYPE=$CMAKE_BUILD_TYPE \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=13.3 \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
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
if [[ -z "${JOBS:-}" ]]; then
  LOGICAL_CPUS="$(sysctl -n hw.logicalcpu 2>/dev/null || echo 1)"
  if (( LOGICAL_CPUS >= 2 )); then JOBS=2; else JOBS=1; fi
fi
JOBS_FLAG="-j $JOBS"
echo "==> native parallelism: $JOBS job(s)"

# Backends that ship in CrispASR today, mapped 1:1 to add_library(...) targets
# in src/CMakeLists.txt. The crispasr-lib link step auto-pulls deps, but
# listing them here ensures build errors surface early.
BACKEND_TARGETS=(
  # ASR
  parakeet canary canary_qwen canary_ctc lfm2_audio qwen3_asr cohere
  granite_speech granite_nle nemotron gigaam sidon mini-omni2 higgs_stt
  voxtral voxtral4b voxtral_tts wav2vec2-ggml glm-asr kyutai-stt firered-asr
  funasr paraformer sensevoice omniasr
  moonshine moonshine_streaming gemma4_e2b mimo_tokenizer mimo_asr ark_asr
  vibevoice moss_audio moss_transcribe moss_transcribe_diarize
  # TTS
  qwen3_tts moss_tts moss_tts_local miotts miocodec omnivoice orpheus
  piano-transcription audioseal chatterbox tada-tts tada-encoder tada-codec
  indextts kokoro piper-tts bananamind-tts irodori-tts
  voxcpm2_tts cosyvoice3_tts f5-tts outetts
  bark-tts csm-tts dia-tts fastpitch-tts parler-tts speecht5-tts
  pocket-tts zonos-tts melotts bert-encoder openvoice2 kugelaudio
  # Translation
  m2m100 t5_translate
  # Post-processing & LID
  crisp_punc crisp_truecase crisp_lid
  pyannote-seg silero-lid ecapa-lid firered-lid firered-vad marblenet-vad
  crispasr-vad-encdec titanet ctc-align
  # Source separation / music analysis
  htdemucs beat-this rvc-svc beatrice-pitch btc-chords tabcnn crepe
  mel-band-roformer
)

echo "==> build backend statics (${#BACKEND_TARGETS[@]} targets)"
"$REPO_ROOT/scripts/check_build_load.sh"
cmake --build "$BUILDDIR" $JOBS_FLAG --target "${BACKEND_TARGETS[@]}"

echo "==> link libwhisper.dylib"
"$REPO_ROOT/scripts/check_build_load.sh"
cmake --build "$BUILDDIR" $JOBS_FLAG --target crispasr-lib

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
  # Do not use grep -q under pipefail: it exits after the first match, nm gets
  # SIGPIPE, and the successful lookup is incorrectly reported as missing.
  if ! nm -gU "$LIBPATH" 2>/dev/null | grep -F "$1" >/dev/null; then
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
  GLINT_BUILD="${GLINT_BUILD_DIR:-$GLINT_DIR/build}"
  GLINT_NEEDS_CONFIGURE=0
  if [[ $REBUILD_CMAKE == 1 || ! -f "$GLINT_BUILD/CMakeCache.txt" ]]; then
    GLINT_NEEDS_CONFIGURE=1
  else
    GLINT_CACHED_DEPLOYMENT=$(sed -n 's/^CMAKE_OSX_DEPLOYMENT_TARGET:STRING=//p' "$GLINT_BUILD/CMakeCache.txt" | head -1)
    GLINT_CACHED_ARCHS=$(sed -n 's/^CMAKE_OSX_ARCHITECTURES:STRING=//p' "$GLINT_BUILD/CMakeCache.txt" | head -1)
    if [[ "$GLINT_CACHED_DEPLOYMENT" != "11.0" || "$GLINT_CACHED_ARCHS" != "arm64" ]]; then
      GLINT_NEEDS_CONFIGURE=1
    fi
  fi
  if [[ $GLINT_NEEDS_CONFIGURE == 1 ]]; then
    cmake -S "$GLINT_DIR" -B "$GLINT_BUILD" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 \
      -DCMAKE_OSX_ARCHITECTURES=arm64 >/dev/null
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

# Build CrispEmbed ourselves instead of trusting the pod's downloaded dylib.
# That release asset may have been compiled by a newer SDK without an explicit
# deployment target (the 0.17.8 asset reports minos 26.0). Its shared target
# embeds ggml statically, which also avoids the pod's ggml ABI collision with
# CrispASR's newer libggml set in the flat Frameworks directory.
echo "==> build libcrispembed.dylib"
CRISPEMBED_NEEDS_CONFIGURE=0
if [[ $REBUILD_CMAKE == 1 || ! -f "$CRISPEMBED_BUILD/CMakeCache.txt" ]]; then
  CRISPEMBED_NEEDS_CONFIGURE=1
else
  CRISPEMBED_CACHED_DEPLOYMENT=$(sed -n 's/^CMAKE_OSX_DEPLOYMENT_TARGET:STRING=//p' "$CRISPEMBED_BUILD/CMakeCache.txt" | head -1)
  CRISPEMBED_CACHED_ARCHS=$(sed -n 's/^CMAKE_OSX_ARCHITECTURES:STRING=//p' "$CRISPEMBED_BUILD/CMakeCache.txt" | head -1)
  CRISPEMBED_CACHED_AUDIO=$(sed -n 's/^CRISP_AUDIO_DIR:PATH=//p' "$CRISPEMBED_BUILD/CMakeCache.txt" | head -1)
  if [[ "$CRISPEMBED_CACHED_DEPLOYMENT" != "12.0" || "$CRISPEMBED_CACHED_ARCHS" != "arm64" ||
        "$CRISPEMBED_CACHED_AUDIO" != "$CRISPEMBED_BUILD/disabled/crisp_audio" ]]; then
    CRISPEMBED_NEEDS_CONFIGURE=1
  fi
fi
if [[ $CRISPEMBED_NEEDS_CONFIGURE == 1 ]]; then
  cmake -S "$CRISPEMBED_DIR" -B "$CRISPEMBED_BUILD" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DBUILD_SHARED_LIBS=OFF \
    -DCRISPEMBED_BUILD_SHARED=ON \
    -DGGML_NATIVE=OFF \
    -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON \
    -DCRISP_AUDIO_DIR="$CRISPEMBED_BUILD/disabled/crisp_audio" \
    -DCRISP_PUNC_DIR="$CRISPEMBED_BUILD/disabled/crisp_punc" \
    -DCRISP_LID_DIR="$CRISPEMBED_BUILD/disabled/crisp_lid" \
    -DCRISP_TRUECASE_DIR="$CRISPEMBED_BUILD/disabled/crisp_truecase"
fi
"$REPO_ROOT/scripts/check_build_load.sh"
cmake --build "$CRISPEMBED_BUILD" $JOBS_FLAG --target crispembed-shared

# ---------------------------------------------------------------------------
# Step 3: flutter build
# ---------------------------------------------------------------------------
cd "$REPO_ROOT"
echo "==> generate bundled-version manifest"
CRISPASR_DIR="$CRISPASR_DIR" CRISPEMBED_DIR="$CRISPEMBED_DIR" \
  GLINT_DIR="$GLINT_DIR" bash "$REPO_ROOT/scripts/gen_build_info.sh"

echo "==> flutter pub get"
flutter pub get >/dev/null

echo "==> flutter build macos $FLUTTER_FLAG"
# The native dependency build may have raised the average since the earlier
# checks. Do not start Xcode/Flutter compilation on top of a saturated host.
"$REPO_ROOT/scripts/check_build_load.sh"
# Xcode's explicit PCM cache is sensitive to non-APFS/external build volumes:
# a missing Cocoa/Foundation PCM makes otherwise valid builds fail
# nondeterministically. Keep this relatively small, rebuildable cache on the
# local temporary volume while all large products remain on external storage.
XCODE_CACHE_TAG="$(xcodebuild -version | tr '\n ' '__' | tr -cd '[:alnum:]_.-')"
MODULE_CACHE_DIR="${MODULE_CACHE_DIR:-/tmp/crisperweaver-${UID}-${XCODE_CACHE_TAG}-module-cache}"
CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$MODULE_CACHE_DIR}"
export MODULE_CACHE_DIR CLANG_MODULE_CACHE_PATH
mkdir -p "$MODULE_CACHE_DIR"
echo "==> Xcode module cache: $MODULE_CACHE_DIR"
# CocoaPods runs under Homebrew ruby, but a chruby line in ~/.zshrc
# exports GEM_PATH/GEM_HOME for a DIFFERENT ruby. pod then dies with
# "Could not find 'nkf'", flutter reports "CocoaPods not installed or
# not in valid state", skips pod install, and produces no .app at all.
# Harmless on CI, where neither var is set.
unset GEM_PATH GEM_HOME
set +e
flutter build macos $FLUTTER_FLAG 2>&1 \
  | grep -vE "(Run script build phase|Metal\.xctoolchain)"
FLUTTER_STATUS=${PIPESTATUS[0]}
set -e
if [[ $FLUTTER_STATUS -ne 0 ]]; then
  echo "error: flutter build macos failed with status $FLUTTER_STATUS" >&2
  exit "$FLUTTER_STATUS"
fi

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
  CRISPASR_BUILD_DIR="$BUILDDIR" \
  CRISPEMBED_DIR="$CRISPEMBED_DIR" \
  CRISPEMBED_BUILD_DIR="$CRISPEMBED_BUILD" \
  GLINT_DIR="$GLINT_DIR" \
  GLINT_BUILD_DIR="${GLINT_BUILD_DIR:-$GLINT_DIR/build}" \
  "$REPO_ROOT/scripts/bundle_macos_dylibs.sh" "$APP"

echo
echo "==> done: $APP"
echo "    Open it with:  open '$APP'"
