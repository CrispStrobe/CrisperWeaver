#!/usr/bin/env bash
# Refuse to start a large compile while this machine is already saturated.
#
# WAIT, don't refuse on sight. The 1-minute load average is a trailing
# figure: right after a checkout, a toolchain install or the previous build
# step it still reflects work that has already finished. Reading it once and
# exiting turns "this machine was busy a minute ago" into a hard failure.
#
# That is not hypothetical — it is how this guard first failed. On a
# 3-logical-CPU macOS CI runner it read 1m=5.04 against a limit of 3 within
# a second of the job starting, while the only load was the setup steps that
# had just completed, and the macOS build job could never start.
#
# So poll until the average falls under the limit, and only then give up.
# A genuinely saturated machine — the case this exists for — still refuses,
# just BUILD_LOAD_WAIT_SECS later. A machine that merely looks busy proceeds.
#
# Env:
#   BUILD_LOAD_MAX        max 1-minute load before a large compile starts
#                         (default: logical CPU count)
#   BUILD_LOAD_WAIT_SECS  how long to wait for it to fall (default: 300;
#                         0 disables waiting and restores check-once)
#   BUILD_LOAD_POLL_SECS  seconds between polls (default: 10)
set -euo pipefail

CPUS="$(sysctl -n hw.logicalcpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"

read_load() {
  local load
  load="$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')"
  if [[ -z "$load" ]]; then
    load="$(uptime | sed -E 's/.*load averages?:[[:space:]]*([0-9.]+).*/\1/')"
  fi
  printf '%s' "$load"
}

under_limit() {
  awk -v load="$1" -v limit="$2" 'BEGIN { exit !(load <= limit) }'
}

MAX_LOAD="${BUILD_LOAD_MAX:-$CPUS}"
WAIT_SECS="${BUILD_LOAD_WAIT_SECS:-300}"
POLL_SECS="${BUILD_LOAD_POLL_SECS:-10}"

LOAD="$(read_load)"
printf '==> system load preflight: 1m=%s, limit=%s, logical CPUs=%s\n' \
  "$LOAD" "$MAX_LOAD" "$CPUS"

if under_limit "$LOAD" "$MAX_LOAD"; then
  exit 0
fi

if [[ "$WAIT_SECS" -le 0 ]]; then
  echo "error: system is already saturated; refusing to start a large compile" >&2
  echo "       Wait for load to fall, or deliberately set BUILD_LOAD_MAX to a higher limit." >&2
  exit 75
fi

printf '==> load is above the limit; waiting up to %ss for it to fall\n' \
  "$WAIT_SECS"

WAITED=0
while [[ "$WAITED" -lt "$WAIT_SECS" ]]; do
  sleep "$POLL_SECS"
  WAITED=$((WAITED + POLL_SECS))
  LOAD="$(read_load)"
  printf '    %ss elapsed, 1m=%s (limit %s)\n' "$WAITED" "$LOAD" "$MAX_LOAD"
  if under_limit "$LOAD" "$MAX_LOAD"; then
    echo "==> load settled; starting the build"
    exit 0
  fi
done

echo "error: system still saturated after ${WAIT_SECS}s (1m=$LOAD, limit=$MAX_LOAD);" >&2
echo "       refusing to start a large compile." >&2
echo "       Raise BUILD_LOAD_MAX, or set BUILD_LOAD_WAIT_SECS to wait longer." >&2
exit 75
