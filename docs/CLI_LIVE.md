# Live microphone captions from the CLI

Run from this checkout. The launcher uses the Dart VM directly so macOS retains
`DYLD_LIBRARY_PATH`; Flutter/Dart shell wrappers can strip it. FFmpeg must be on
PATH, or pass `--ffmpeg /path/to/ffmpeg`.

```sh
scripts/run_cli.sh live --list-devices
scripts/live_sennheiser.sh
# A finite capture, useful for calibration:
scripts/live_sennheiser.sh --duration 60
```

The local preset explicitly selects the attached Sennheiser SP 20 for Lync,
Cohere Q8, fixed German, Silero VAD and 3-second draft updates. It saves the exact
16 kHz mono input WAV and JSONL events in `~/Documents/CrisperWeaver/live/`.
Ctrl+C stops capture, flushes pending words and repairs the WAV header. `--duration`
is measured in captured audio seconds and starts after model loading.

Generic use:

```sh
scripts/run_cli.sh live --device 'Sennheiser SP 20 for Lync' \
  --backend cohere --model /path/to/cohere.gguf --language de \
  --vad-model /path/to/silero.bin --save-audio take.wav --events take.jsonl
```

Names or unique name fragments are preferred over AVFoundation IDs, which can
change when devices reconnect. Ambiguous or missing selections fail; the command
never silently falls back to the built-in microphone. Microphone capture currently
supports macOS AVFoundation. Device enumeration returning a nonzero FFmpeg status
is normal; successful PCM capture is checked separately. macOS microphone access
must be allowed for the terminal/capture process. System-audio screen-capture
permission is not involved in this route.

This uses the **same ASR isolate, VAD, sentence committer and streaming dispatch as
the GUI**, without loading Flutter. Capture, WAV saving and level reporting run
independently from recognition. Cohere is buffered ASR, not a native streaming
model. Native stateful models retain their encoder/decoder state per utterance.
The older `stream file.wav` command is still a file-decoding command.
The GUI also uses 3-second Cohere updates and caps its Cohere CPU threads at 3,
matching the calibrated local preset; other GUI backends retain their defaults.

Every event carries a UTC timestamp. `unit` is committed text, `tail` is revisable,
`stats` reports decode time and lag behind capture, `level` reports 5-second RMS
and peak dBFS, and `summary` records audio duration and maximum lag. Lag is not
sentence-commit latency: draft updates and final silence add latency of their own.
`--json` emits the event stream on stdout; diagnostics go to stderr. Verbose native engine messages are suppressed by default so captions remain
readable; use `--native-logs` when diagnosing model/VAD loading. The default lag watchdog stops at 20 seconds
rather than allowing recognition to queue audio indefinitely. Existing output
files are refused. WAV saving streams to disk instead of retaining the recording
in memory.

Cohere's initial drafts wait for three seconds of context, retain up to 25 seconds
of acoustic context after text commits, and VAD uses threshold 0.35. Real-time replay on difficult German room audio improved relative to the
previous 1-second draft configuration, but still makes word errors and occasional
false text. Short, real utterances are decoded on finalization. No claim of
human-verified accuracy is made. Native timestamps remain approximate.

For sustained calibration, record at least two minutes and compare update
intervals by replaying the identical WAV. `--step-ms 5000` trades slower drafts
for fewer overlapping Cohere decodes. The summary includes `p95StepMs` and
`periodicProcessingFraction` (time in periodic VAD/ASR steps divided by audio
duration, excluding the final flush). This fraction is not system CPU usage.
Stats include `audioUntilSec` and `decodedUntilSec` for tracing progress.

To compare raw audio, bounded gain and gentle cleanup, use a local Python
environment with numpy/scipy and run:

```sh
python scripts/evaluate_live_recording.py take.wav --out comparison \
  --model /path/to/cohere.gguf --lib /path/to/libcrispasr.dylib
```

It preserves the source, writes three matched snippets per variant, and creates
`comparison.html` with audio players, transcripts, levels and warm decode timings.
The output directory must be new. Gain targets -26 dBFS RMS, caps amplification
at 10 dB and preserves -3 dBFS peak headroom. Cleanup adds a 70 Hz highpass and
light FFmpeg noise reduction. Neither is automatically enabled for live ASR:
changed model output is not evidence of improved accuracy without a checked
reference. No cloud requests are made.

For repeatable tests, feed an existing recording at real-time speed:

```sh
scripts/run_cli.sh live --input take.wav --backend cohere \
  --model /path/to/cohere.gguf --language de --events replay.jsonl
```

Local preset overrides: `CW_MIC`, `CW_ASR_MODEL`, `CW_VAD_MODEL`,
`CW_LIVE_OUTPUT_DIR`; launcher override: `CW_DART_BIN`. Explicit CLI `--lib` or
`CRISPASR_LIB` takes priority over sibling build discovery. This checkout prefers
`CrispASR-streaming-local` when no library override is supplied.
