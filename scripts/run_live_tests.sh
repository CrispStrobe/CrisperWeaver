#!/usr/bin/env bash
# Run CrisperWeaver live/slow tests against the locally-built CrispASR
# dylib and the q4_k models on disk (PLAN §9.1).
#
# Live tests load real GGUFs and decode audio, so they are tagged
# `slow` and self-skip unless their model is resolvable. This script
# points the shared locator (test/support/crispasr_models.dart) at the
# built dylib + the on-disk models dir, then runs the slow suite.
#
# Usage:
#   scripts/run_live_tests.sh                 # all slow tests
#   scripts/run_live_tests.sh test/vad_live_test.dart   # one file
#
# Env overrides (all optional):
#   CRISPASR_LIB           explicit dylib path
#   CRISPASR_MODELS_DIR    models dir (default /Volumes/backups/ai/crispasr)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Disk policy: keep build/test temp off the chronically-full system vol.
if [ -d /Volumes/backups/code ]; then
  export TMPDIR="${TMPDIR:-/Volumes/backups/code/tmp}"
  mkdir -p "$TMPDIR"
fi

# Resolve the dylib if the caller did not pin one.
if [ -z "${CRISPASR_LIB:-}" ]; then
  for c in \
    ../CrispASR/build/src/libcrispasr.dylib \
    ../CrispASR/build-flutter-bundle/src/libcrispasr.dylib \
    ../CrispASR/build/src/libwhisper.dylib \
    ../CrispASR/build-vk/src/libcrispasr.dylib \
    ../CrispASR/build/src/libcrispasr.so; do
    if [ -f "$c" ]; then CRISPASR_LIB="$(cd "$(dirname "$c")" && pwd)/$(basename "$c")"; break; fi
  done
fi
export CRISPASR_LIB="${CRISPASR_LIB:-}"
export CRISPASR_MODELS_DIR="${CRISPASR_MODELS_DIR:-/Volumes/backups/ai/crispasr}"

if [ -z "$CRISPASR_LIB" ] || [ ! -f "$CRISPASR_LIB" ]; then
  echo "WARN: no libcrispasr dylib found — live tests will self-skip." >&2
else
  echo "CRISPASR_LIB=$CRISPASR_LIB"
fi
echo "CRISPASR_MODELS_DIR=$CRISPASR_MODELS_DIR"

TARGET="${1:-}"
echo "== flutter test --tags slow ${TARGET} =="
flutter test --tags slow ${TARGET}
