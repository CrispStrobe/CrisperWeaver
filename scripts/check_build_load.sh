#!/usr/bin/env bash
# Refuse to start a large compile while this machine is already saturated.
set -euo pipefail

CPUS="$(sysctl -n hw.logicalcpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
LOAD="$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')"
if [[ -z "$LOAD" ]]; then
  LOAD="$(uptime | sed -E 's/.*load averages?:[[:space:]]*([0-9.]+).*/\1/')"
fi
MAX_LOAD="${BUILD_LOAD_MAX:-$CPUS}"

printf '==> system load preflight: 1m=%s, limit=%s, logical CPUs=%s\n' \
  "$LOAD" "$MAX_LOAD" "$CPUS"

if ! awk -v load="$LOAD" -v limit="$MAX_LOAD" 'BEGIN { exit !(load <= limit) }'; then
  echo "error: system is already saturated; refusing to start a large compile" >&2
  echo "       Wait for load to fall, or deliberately set BUILD_LOAD_MAX to a higher limit." >&2
  exit 75
fi
