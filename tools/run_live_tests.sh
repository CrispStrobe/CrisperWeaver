#!/usr/bin/env bash
#
# Run the CrisperWeaver live/slow suites against the locally-built CrispASR
# shared library and the GGUF weights on this box, one suite at a time.
#
# Why this exists next to scripts/run_live_tests.sh: that script is the
# macOS dev-box shape — it points the shared locator at a single
# `$CRISPASR_MODELS_DIR` and runs `flutter test --tags slow` once, over
# everything. Neither half works here. This is an 8 GB Linux box, and:
#
#   * One `flutter test` over every slow suite loads several models into
#     one process. Two multi-hundred-MB GGUFs resident at once is enough
#     to get the whole run OOM-killed, and an OOM kill looks nothing like
#     a test failure — you get a truncated log and no verdict. So every
#     suite is a separate `flutter test` invocation with `-j 1`, and the
#     PASS/FAIL verdict is recorded per suite.
#
#   * Pointing `CRISPASR_MODELS_DIR` at /mnt/storage/gguf-models would
#     silently arm the multi-GB entries in the locator's table
#     (madlad400-3b 2.0 GB, wmt21-dense-24-wide 2.7 GB, voxcpm2 1.7 GB).
#     Instead this script exports one `CRISPASR_TEST_<KEY>_MODEL` per
#     model and refuses any file over $MAX_MODEL_BYTES. The weights are
#     used from where they already live — nothing is copied or symlinked
#     into a models dir.
#
# Usage:
#   tools/run_live_tests.sh                      # every default suite
#   tools/run_live_tests.sh test/vad_live_test.dart [...]   # only these
#
# Env overrides (all optional):
#   MODELS_DIR        where the GGUFs live   (default /mnt/storage/gguf-models)
#   KOKORO_DIR        where the kokoro model + voicepack live
#                     (default: the session scratch copy if it still
#                     exists, else $MODELS_DIR)
#   WHISPER_MODEL     explicit ggml-*.bin for the ASR leg
#   CRISPASR_LIB      explicit libcrispasr.so
#   CRISPASR_BUILD    CrispASR build dir     (default /mnt/volume1/CrispASR/build)
#   FLUTTER           flutter binary
#   MAX_MODEL_BYTES   per-file ceiling       (default 1 GiB)
#   RUN_HEAVY=1       lift the ceiling and add the heavyweight suites.
#                     Do NOT set this on a box with 8 GB of RAM unless
#                     you are watching it.
#   RUN_NETWORK=0     skip the network-dependent 'live'-tagged suite
#
# Exit status: 0 only when every suite that ran reported success.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# ---------------------------------------------------------------------------
# Toolchain + native library
# ---------------------------------------------------------------------------

FLUTTER="${FLUTTER:-}"
if [ -z "$FLUTTER" ]; then
  if command -v flutter >/dev/null 2>&1; then
    FLUTTER="$(command -v flutter)"
  elif [ -x /mnt/volume1/toolchain/flutter/bin/flutter ]; then
    FLUTTER=/mnt/volume1/toolchain/flutter/bin/flutter
  else
    echo "FATAL: no flutter binary — set FLUTTER=/path/to/flutter" >&2
    exit 1
  fi
fi

CRISPASR_BUILD="${CRISPASR_BUILD:-/mnt/volume1/CrispASR/build}"

# libcrispasr.so links against the ggml family, which is NOT installed
# system-wide — dlopen() fails with "libggml-base.so.0: cannot open shared
# object file" unless both directories are on the loader path. That failure
# surfaces inside Dart as a plain "dylib not found" self-skip, i.e. a green
# run that tested nothing, which is exactly the outcome this line prevents.
export LD_LIBRARY_PATH="${CRISPASR_BUILD}/src:${CRISPASR_BUILD}/ggml/src${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

if [ -z "${CRISPASR_LIB:-}" ]; then
  for c in \
    "${CRISPASR_BUILD}/src/libcrispasr.so" \
    "${CRISPASR_BUILD}/src/libwhisper.so" \
    "${CRISPASR_BUILD}/src/libcrispasr.dylib" \
    "${CRISPASR_BUILD}/src/libwhisper.dylib"; do
    if [ -f "$c" ]; then CRISPASR_LIB="$c"; break; fi
  done
fi
export CRISPASR_LIB="${CRISPASR_LIB:-}"

if [ -z "$CRISPASR_LIB" ] || [ ! -f "$CRISPASR_LIB" ]; then
  # Not fatal: the suites self-skip cleanly without the library. But say so
  # loudly, because "all green, everything skipped" is the failure mode this
  # whole script exists to make visible.
  echo "WARN: no libcrispasr found under ${CRISPASR_BUILD}/src —" >&2
  echo "      every model-backed test will SELF-SKIP (green but vacuous)." >&2
fi

# ---------------------------------------------------------------------------
# Weights. One env var per model; each guarded on the file existing and on
# staying under the size ceiling.
# ---------------------------------------------------------------------------

MODELS_DIR="${MODELS_DIR:-/mnt/storage/gguf-models}"
MAX_MODEL_BYTES="${MAX_MODEL_BYTES:-1073741824}"   # 1 GiB
if [ "${RUN_HEAVY:-0}" = "1" ]; then
  MAX_MODEL_BYTES=$((1024 * 1024 * 1024 * 1024))   # effectively unlimited
fi

# The kokoro pair was staged into a session scratch dir; that directory is
# transient, so fall back to the durable copy under $MODELS_DIR.
_scratch_kokoro="/tmp/claude-1000/-mnt-volume1-CrisperWeaver/16e97690-54a8-4a51-a399-4888ced06cec/scratchpad/gui/home/models/whisper_cpp"
if [ -n "${KOKORO_DIR:-}" ]; then
  :
elif [ -f "${_scratch_kokoro}/kokoro-82m-q8_0.gguf" ]; then
  KOKORO_DIR="$_scratch_kokoro"
else
  KOKORO_DIR="$MODELS_DIR"
fi

_size() { stat -c%s "$1" 2>/dev/null || stat -f%z "$1" 2>/dev/null || echo 0; }

ARMED=()
SKIPPED_BIG=()

# export_var VAR candidate [candidate...]
# Exports VAR to the first candidate that exists and fits under the ceiling.
# Candidates are in preference order, so a q4_k quant can shadow a bigger
# sibling of the same model.
export_var() {
  local var="$1"; shift
  local cand sz
  # Respect a caller-supplied override: a pre-set var is the caller telling
  # us exactly which weight to test. Clobbering it (as this used to)
  # silently redirected two days of silero-lid debugging onto the wrong
  # file — the caller exported the f32 model, the runner re-exported q8_0.
  if [ -n "${!var:-}" ]; then
    if [ -f "${!var}" ]; then
      ARMED+=("$var=$(basename "${!var}") (caller override)")
      return 0
    fi
    echo "WARN: $var preset to missing file '${!var}' — falling back to candidates" >&2
  fi
  for cand in "$@"; do
    [ -f "$cand" ] || continue
    sz="$(_size "$cand")"
    if [ "$sz" -gt "$MAX_MODEL_BYTES" ]; then
      SKIPPED_BIG+=("$var -> $(basename "$cand") ($((sz / 1024 / 1024)) MB)")
      continue
    fi
    export "$var=$cand"
    ARMED+=("$var=$(basename "$cand")")
    return 0
  done
  return 0
}

# ---- fixtures -------------------------------------------------------------
export_var CRISPASR_TEST_JFK_WAV \
  /mnt/volume1/CrispASR/samples/jfk.wav \
  "$ROOT/test/jfk.wav"

# ---- ASR ------------------------------------------------------------------
# The plain ASR leg (roundtrips, backend_dispatch, cli_test). English-only
# is fine here — every fixture and every synth phrase in the suite is
# English, and base.en is the most accurate English decoder on this box.
export_var CRISPASR_TEST_WHISPER_MODEL \
  "${WHISPER_MODEL:-}" \
  "$MODELS_DIR/c4-live/ggml-base.en.bin" \
  "$MODELS_DIR/ggml-base.en.bin"
# CRISPASR_TINY_MODEL is a different contract: crispasr_live_test.dart and
# s26_integration_live_test.dart predate the shared locator and explicitly
# want a *tiny.en* checkpoint for plain English ASR, so the English-only
# build is the right file there rather than a compromise.
export_var CRISPASR_TINY_MODEL \
  /mnt/volume1/CrispASR/models/ggml-tiny.en.bin \
  "$MODELS_DIR/ggml-tiny.en.bin"
# The locator's `whisper_tiny` key means MULTILINGUAL tiny, and it is armed
# only if such a file turns up — never with a .en build. lid_live_test.dart
# asserts on whisper_lang_auto_detect, which an English-only checkpoint
# cannot answer meaningfully, so a silent substitution here would turn a
# missing-model skip into a mystery failure.
export_var CRISPASR_TEST_WHISPER_TINY_MODEL \
  "$MODELS_DIR/ggml-tiny.bin" \
  "$MODELS_DIR/ggml-base.bin" \
  "$MODELS_DIR/ggml-small.bin"
export_var CRISPASR_TEST_MOONSHINE_TINY_MODEL "$MODELS_DIR/moonshine-tiny-q4_k.gguf"
export_var CRISPASR_TEST_PARAKEET_110M_MODEL  "$MODELS_DIR/parakeet-tdt_ctc-110m-q4_k.gguf"
export_var CRISPASR_TEST_FASTCONFORMER_CTC_MODEL \
  "$MODELS_DIR/stt-en-fastconformer-ctc-large-q4_k.gguf"
export_var CRISPASR_TEST_WAV2VEC2_MODEL       "$MODELS_DIR/wav2vec2-xlsr-en-q4_k.gguf"
export_var CRISPASR_TEST_PARAFORMER_ZH_MODEL  "$MODELS_DIR/paraformer-zh-q4_k.gguf"
export_var CRISPASR_TEST_NEMOTRON_MODEL       "$MODELS_DIR/nemotron-3.5-asr-streaming-0.6b-q4_k.gguf"

# ---- language ID ----------------------------------------------------------
# f32 ONLY for silero-lid: the q8_0/q5_0 artifacts are broken — the tiny
# classifier answers junk (pa-IN @ p=0.017) on the ggml path and NaN
# confidence on the legacy path, verified natively 2026-09-02. The f32 is
# 16 MB; there is nothing to save. (This candidate order was the true
# cause of the "silero misidentifies languages" scare.)
export_var CRISPASR_TEST_SILERO_LID_MODEL \
  "$MODELS_DIR/silero-lid-lang95-f32.gguf" \
  "$MODELS_DIR/silero-lid-95.gguf"
export_var CRISPASR_TEST_CLD3_MODEL    "$MODELS_DIR/cld3-f32.gguf"
export_var CRISPASR_TEST_GLOTLID_MODEL "$MODELS_DIR/lid-glotlid-q4_k.gguf"

# ---- VAD / diarization / speaker / alignment ------------------------------
export_var CRISPASR_TEST_WHISPER_VAD_MODEL   "$MODELS_DIR/whisper-vad-asmr-q4_k.gguf"
export_var CRISPASR_TEST_MARBLENET_VAD_MODEL "$MODELS_DIR/marblenet-vad.gguf"
export_var CRISPASR_TEST_FIRERED_VAD_MODEL   "$MODELS_DIR/firered-vad.gguf"
export_var CRISPASR_TEST_PYANNOTE_MODEL      "$MODELS_DIR/pyannote-seg-3.0.gguf"
export_var CRISPASR_TEST_CANARY_ALIGNER_MODEL "$MODELS_DIR/canary-ctc-aligner-q4_k.gguf"
# TitaNet is spelled two ways across the suites: speaker_id_live_test.dart
# predates the shared locator and reads CRISPASR_TITANET_MODEL, while
# speaker_textlid_test.dart uses the locator's CRISPASR_TEST_*_MODEL form.
export_var CRISPASR_TEST_TITANET_MODEL "$MODELS_DIR/titanet-large.gguf"
export_var CRISPASR_TITANET_MODEL      "$MODELS_DIR/titanet-large.gguf"

# ---- punctuation ----------------------------------------------------------
# The suites load whatever shape they are handed through PuncModel.open, so
# quantised first: fullstop-punc.gguf is 1.1 GB and fullstop-punc-f32emb is
# 1.6 GB, both of which the ceiling rejects by default anyway.
export_var CRISPASR_TEST_FULLSTOP_PUNC_MODEL \
  "$MODELS_DIR/fullstop-punc-q4_k.gguf" \
  "$MODELS_DIR/fullstop-punc-q8_0.gguf" \
  "$MODELS_DIR/fullstop-punc.gguf"
export_var CRISPASR_TEST_FIREREDPUNC_MODEL "$MODELS_DIR/fireredpunc-q4_k.gguf"

# ---- translation ----------------------------------------------------------
# q4_k (284 MB) rather than the q8_0 (526 MB) the locator's table names, and
# madlad (2.0 GB) is left unset so translation_live_test falls through to
# m2m100 instead of paging in a 2 GB beam search.
export_var CRISPASR_TEST_M2M100_MODEL \
  "$MODELS_DIR/m2m100-418m-q4_k.gguf" \
  "$MODELS_DIR/m2m100-418m-q8_0.gguf"

# ---- TTS ------------------------------------------------------------------
export_var CRISPASR_TEST_KOKORO_MODEL "$KOKORO_DIR/kokoro-82m-q8_0.gguf" \
  "$MODELS_DIR/kokoro-82m-q8_0.gguf"
export_var CRISPASR_TEST_KOKORO_VOICE "$KOKORO_DIR/kokoro-voice-af_heart.gguf" \
  "$MODELS_DIR/kokoro-voice-af_heart.gguf"
export_var CRISPASR_TEST_CHATTERBOX_MODEL "$MODELS_DIR/chatterbox-t3-q4_k.gguf"
export_var CRISPASR_TEST_CHATTERBOX_S3GEN "$MODELS_DIR/chatterbox-s3gen-q4_k.gguf"

# ---- heavyweights: only with RUN_HEAVY=1 ----------------------------------
if [ "${RUN_HEAVY:-0}" = "1" ]; then
  export_var CRISPASR_TEST_MADLAD_MODEL     "$MODELS_DIR/madlad400-3b-mt-q4_k.gguf"
  export_var CRISPASR_TEST_WMT21_EN_X_MODEL "$MODELS_DIR/wmt21-dense-24-wide-en-x-q4_k.gguf"
  export_var CRISPASR_TEST_VOXCPM2_MODEL    "$MODELS_DIR/voxcpm2-q4_k.gguf"
  export_var CRISPASR_TEST_VIBEVOICE_MODEL  "$MODELS_DIR/vibevoice-1.5b-q4_k.gguf"
  export_var CRISPASR_TEST_VIBEVOICE_VOICE  "$MODELS_DIR/vibevoice-voice-en-Emma_woman.gguf"
fi

# ---------------------------------------------------------------------------
# Suite list, cheapest first so a broken environment shows up in seconds
# rather than after a 20-minute decode.
# ---------------------------------------------------------------------------

SLOW_SUITES=(
  # no model at all — pure dylib / DSP
  test/watermark_live_test.dart
  test/audio_enhancement_live_test.dart
  # small standalone models
  test/silero_lid_live_test.dart
  test/lid_live_test.dart
  test/lid_dispatch_live_test.dart
  test/punc_live_test.dart
  test/speaker_id_live_test.dart
  test/speaker_textlid_test.dart
  test/diarization_live_test.dart
  test/vad_live_test.dart
  # ASR
  test/alt_asr_backends_live_test.dart
  test/paraformer_zh_live_test.dart
  test/streaming_asr_live_test.dart
  test/crispasr_live_test.dart
  # alignment
  test/aligner_live_test.dart
  test/canary_ctc_aligner_live_test.dart
  # translation
  test/translation_live_test.dart
  test/verification_matrix_live_test.dart
  # TTS and the roundtrips that consume it
  test/tts_issue_fixes_live_test.dart
  test/synthetic_compliance_live_test.dart
  test/tts_asr_roundtrip_live_test.dart
  test/backend_dispatch_test.dart
  test/cli_test.dart
  # integration sweeps last: they load the most per file
  test/s12_integration_live_test.dart
  test/s26_integration_live_test.dart
  test/reranker_embed_live_test.dart
)

# Suites whose weights are all over the ceiling. Never in the default run.
HEAVY_SUITES=()

if [ "${RUN_HEAVY:-0}" = "1" ] && [ ${#HEAVY_SUITES[@]} -gt 0 ]; then
  SLOW_SUITES+=("${HEAVY_SUITES[@]}")
fi

# 'live' = reaches the network, not the disk. Gated separately because it
# needs no dylib and no weights, and because a box without egress should be
# able to opt out without losing the model suites.
LIVE_SUITES=(
  test/download_engine_live_test.dart
)

# An explicit argument list overrides both.
if [ "$#" -gt 0 ]; then
  SLOW_SUITES=("$@")
  LIVE_SUITES=()
fi

# ---------------------------------------------------------------------------
# Report the environment before spending an hour on it.
# ---------------------------------------------------------------------------

echo "=============================================================="
echo " CrisperWeaver live/slow run"
echo "=============================================================="
echo "flutter          : $FLUTTER"
echo "CRISPASR_LIB     : ${CRISPASR_LIB:-<none>}"
echo "LD_LIBRARY_PATH  : $LD_LIBRARY_PATH"
echo "MODELS_DIR       : $MODELS_DIR"
echo "KOKORO_DIR       : $KOKORO_DIR"
echo "size ceiling     : $((MAX_MODEL_BYTES / 1024 / 1024)) MB (RUN_HEAVY=${RUN_HEAVY:-0})"
echo
echo "armed weights (${#ARMED[@]}):"
if [ ${#ARMED[@]} -eq 0 ]; then
  echo "  (none — every model-backed test will self-skip)"
else
  printf '  %s\n' "${ARMED[@]}"
fi
if [ ${#SKIPPED_BIG[@]} -gt 0 ]; then
  echo
  echo "over the size ceiling, NOT armed (${#SKIPPED_BIG[@]}):"
  printf '  %s\n' "${SKIPPED_BIG[@]}"
fi
echo
free -h 2>/dev/null || true
echo

# ---------------------------------------------------------------------------
# Run, one suite per process.
# ---------------------------------------------------------------------------

RESULTS=()
FAILED=0

# run_suite <file> <tag> [VAR=VAL ...]
# One `flutter test` process per suite, with `-j 1`, so a suite that gets
# OOM-killed takes only its own verdict down with it.
run_suite() {
  local file="$1"; shift
  local tag="$1"; shift
  # Anything left is passed to `env` for this invocation only, so a var
  # meant for one suite cannot leak into the next.
  if [ ! -f "$file" ]; then
    RESULTS+=("SKIP($tag) $file  — file not found")
    return 0
  fi
  echo "--------------------------------------------------------------"
  echo "== [$tag] $file"
  echo "--------------------------------------------------------------"
  local start end status
  start="$(date +%s)"
  # `set -e` must not abort the sweep: one failing suite should not hide the
  # verdict for the twenty after it. Hence `|| status=$?` rather than a bare
  # call.
  status=0
  env "$@" "$FLUTTER" test -j 1 --tags "$tag" --reporter expanded "$file" \
    || status=$?
  end="$(date +%s)"
  if [ "$status" -eq 0 ]; then
    RESULTS+=("PASS($tag) $file  [$((end - start))s]")
  else
    RESULTS+=("FAIL($tag) $file  [$((end - start))s, exit $status]")
    FAILED=$((FAILED + 1))
  fi
  echo
}

for suite in "${SLOW_SUITES[@]}"; do
  run_suite "$suite" slow
done

if [ "${RUN_NETWORK:-1}" = "1" ]; then
  for suite in "${LIVE_SUITES[@]}"; do
    # RUN_LIVE_TESTS is the per-test opt-in the live suites check
    # themselves. Scoped to this one invocation so it never reaches the
    # slow suites, where it would also satisfy CrispModels.enabled and
    # change what they consider opted-in.
    run_suite "$suite" live RUN_LIVE_TESTS=1
  done
else
  for suite in "${LIVE_SUITES[@]}"; do
    RESULTS+=("SKIP(live) $suite  — RUN_NETWORK=0")
  done
fi

# ---------------------------------------------------------------------------

echo "=============================================================="
echo " summary"
echo "=============================================================="
printf '%s\n' "${RESULTS[@]}"
echo "--------------------------------------------------------------"
echo "suites: ${#RESULTS[@]}   failed: $FAILED"

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
exit 0
