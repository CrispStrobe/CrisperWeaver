#!/usr/bin/env bash
#
# Run Flutter integration tests on a connected device or emulator.
#
# These tests validate on-device behaviour that unit tests can't cover:
# native library loading, platform channel fallbacks (MediaCodec on
# Android), and audio format decoding through the real pipeline.
#
# Usage:
#   scripts/run_integration_tests.sh                                    # all integration tests
#   scripts/run_integration_tests.sh integration_test/audio_decode_test.dart  # single file
#
# Prerequisites:
#   - A connected Android device/emulator or iOS simulator
#   - The app must build for the target platform (jniLibs/ populated for Android)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

TARGET="${1:-integration_test}"

# Check for connected devices.
DEVICES=$(flutter devices --machine 2>/dev/null | grep -c '"id"' || echo "0")
if [[ "$DEVICES" == "0" ]]; then
  echo "error: no connected devices found. Connect a device or start an emulator." >&2
  echo "  Android:  emulator -avd <name>  or connect via USB" >&2
  echo "  iOS:      open -a Simulator" >&2
  exit 1
fi

echo "==> Running integration tests: $TARGET"
echo "==> Connected devices: $DEVICES"

flutter test "$TARGET" --reporter expanded
