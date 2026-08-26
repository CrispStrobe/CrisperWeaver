#!/usr/bin/env bash
# Launch the exact built bundle and fail if it exits during startup.
set -euo pipefail

APP="${1:-build/macos/Build/Products/Release/crisper_weaver.app}"
SECONDS_TO_WATCH="${SMOKE_SECONDS:-10}"
EXECUTABLE="$APP/Contents/MacOS/crisper_weaver"
[[ -x "$EXECUTABLE" ]] || { echo "error: executable not found: $EXECUTABLE" >&2; exit 2; }

LOG_FILE=$(mktemp -t crisper-weaver-smoke.XXXXXX)
SMOKE_OK=0
cleanup() {
  if [[ -n "${APP_PID:-}" ]] && kill -0 "$APP_PID" 2>/dev/null; then
    kill -TERM "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
  if [[ $SMOKE_OK -eq 1 ]]; then
    rm -f "$LOG_FILE"
  else
    echo "startup log retained at: $LOG_FILE" >&2
  fi
}
trap cleanup EXIT

"$EXECUTABLE" >"$LOG_FILE" 2>&1 &
APP_PID=$!

for ((tick=0; tick<SECONDS_TO_WATCH*4; tick++)); do
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    wait "$APP_PID" || STATUS=$?
    echo "error: app exited during startup (status ${STATUS:-0})" >&2
    tail -80 "$LOG_FILE" >&2
    exit 1
  fi
  sleep 0.25
done

if grep -Eiq 'dyld.*(not loaded|symbol not found)|uncaught exception|fatal error' "$LOG_FILE"; then
  echo "error: fatal startup signature found in app output" >&2
  tail -80 "$LOG_FILE" >&2
  exit 1
fi

SMOKE_OK=1
echo "macOS startup smoke OK: app remained alive for ${SECONDS_TO_WATCH}s"
