#!/usr/bin/env bash
# Build the German-then-English "talk" the live-captions live tests replay
# (test/live_translate/live_pipeline_live_test.dart, CRISPASR_TEST_LIVE_WAV):
# four German sentences, 1.5 s of silence, four English ones, 16 kHz mono.
# Synthesised with the Piper voices through the CrispASR CLI, so it can be
# regenerated anywhere the CLI and two Piper GGUFs are available. CrispASR
# prepends its spoken AI disclaimer to each clip — that is kept: it puts an
# English sentence inside the German half, which the text-LID mode must
# label English.
#
# usage: tools/make_live_talk_fixture.sh [out.wav]
#   CRISPASR_BIN  crispasr CLI           (default: ../CrispASR/build/bin/crispasr)
#   MODELS_DIR    where the Piper GGUFs live (default: /mnt/storage/gguf-models)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CRISPASR_BIN="${CRISPASR_BIN:-$ROOT/../CrispASR/build/bin/crispasr}"
MODELS_DIR="${MODELS_DIR:-/mnt/storage/gguf-models}"
OUT="${1:-$MODELS_DIR/talk_de_en.wav}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

"$CRISPASR_BIN" --backend piper -m "$MODELS_DIR/piper-de_DE-thorsten-medium-f16.gguf" \
  --tts "Herzlich willkommen zur heutigen Sitzung. Wir haben drei Punkte auf der Tagesordnung. Zuerst sprechen wir über die Ergebnisse des letzten Quartals. Die Umsätze sind um zwölf Prozent gestiegen." \
  --tts-output "$TMP/de.wav"
"$CRISPASR_BIN" --backend piper -m "$MODELS_DIR/piper-en_US-lessac-medium-f16.gguf" \
  --tts "Thank you very much. I would like to add a short comment. The growth came mostly from exports to France and Italy. Are there any questions?" \
  --tts-output "$TMP/en.wav"

python3 - "$TMP/de.wav" "$TMP/en.wav" "$OUT" <<'PY'
import sys, wave
import numpy as np
def load(p):
    w = wave.open(p)
    x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32)
    if w.getnchannels() > 1:
        x = x.reshape(-1, w.getnchannels()).mean(1)
    n = int(len(x) * 16000 / w.getframerate())
    return np.interp(np.linspace(0, len(x) - 1, n), np.arange(len(x)), x)
de, en = load(sys.argv[1]), load(sys.argv[2])
sil = np.zeros(int(16000 * 1.5))
y = np.concatenate([sil[:8000], de, sil, en, sil]).clip(-32768, 32767).astype(np.int16)
o = wave.open(sys.argv[3], "w")
o.setnchannels(1); o.setsampwidth(2); o.setframerate(16000); o.writeframes(y.tobytes()); o.close()
print(f"{sys.argv[3]}: {len(y) / 16000:.1f} s")
PY
