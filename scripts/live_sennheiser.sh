#!/usr/bin/env bash
# Local German room-mic preset. Override CW_MIC, CW_ASR_MODEL, CW_VAD_MODEL,
# CW_LIVE_OUTPUT_DIR or pass live CLI options (e.g. --duration 60).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODEL="${CW_ASR_MODEL:-$ROOT/../.crisperweaver-deps/german-asr-comparison/cohere-transcribe-q8_0.gguf}"
VAD="${CW_VAD_MODEL:-$HOME/Applications/CrisperWeaver-local-fixed.app/Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets/assets/vad/silero-v6.2.0-ggml.bin}"
OUT="${CW_LIVE_OUTPUT_DIR:-$HOME/Documents/CrisperWeaver/live}"
mkdir -p "$OUT"
STAMP="$(date '+%Y%m%d-%H%M%S')-$$"
exec "$ROOT/scripts/run_cli.sh" live --device "${CW_MIC:-Sennheiser}" \
  --backend cohere --model "$MODEL" --language de --vad-model "$VAD" \
  --step-ms 3000 --save-audio "$OUT/$STAMP.wav" --events "$OUT/$STAMP.jsonl" "$@"
