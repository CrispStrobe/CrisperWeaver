#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [ -z "${CW_DART_BIN:-}" ]; then
  flutter_tool="$(python3 -c 'import os,shutil; print(os.path.realpath(shutil.which("flutter") or ""))')"
  CW_DART_BIN="$(dirname "$(dirname "$flutter_tool")")/bin/cache/dart-sdk/bin/dart"
fi
ort_lib="$ROOT/../.crisperweaver-deps/onnxruntime-osx-arm64-1.30.0/lib"
if [ -d "$ort_lib" ]; then
  export DYLD_LIBRARY_PATH="$ort_lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
fi
exec "$CW_DART_BIN" bin/crisperweaver.dart "$@"
