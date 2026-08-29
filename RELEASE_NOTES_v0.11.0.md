# CrisperWeaver v0.11.0 — the issue #35 quality round

**Released:** 2026-08-29
**Engines:** CrispASR 0.8.30 · CrispEmbed 0.17.10

Issue #35 was a first-run report from someone using the app the way a
new user does: install, onboard, download a model, synthesise something,
clone a voice, go back. Almost every step broke. This release fixes all
of them — downloads that corrupted themselves on resume, a language
filter that filtered nothing, voices listed twice, an onboarding pass
that downloaded one voice and played another, a voice-clone wizard whose
hand-off silently dropped the clip, screens with no way back, and a
handful of controls that were visible but not connected to anything.

Everything below was re-checked end to end on a real build, not only in
tests: the full GUI was driven under Xvfb against the real inference
engine, and every fix has a regression test that fails on the old code.

---

## Highlights

### Downloads — resume no longer corrupts the file

- **The bug.** A resumed download sent the `Range` header correctly, but
  the file it wrote was overwritten with only the resumed tail — the
  bytes already on disk were thrown away. The result was a file short by
  exactly the amount already fetched, which surfaced as a checksum
  mismatch, an "incomplete" error (`expected 745121600, got 674342336`),
  or — when the shortfall fell inside the old size tolerance — a
  silently accepted file that failed to load later.
- **The fix.** A new streaming `DownloadEngine` (`model_service.dart`)
  replaces `Dio.download()` for model transfers:
  - appends to the partial file only when the server answers `206` with
    a `Content-Range` that matches the offset we asked for;
  - restarts from zero on a `200` or on a range mismatch;
  - treats `416` as "already complete";
  - verifies the finished file against the **server's** reported length,
    not the catalogue's size estimate — the tolerance that used to mask
    truncation is gone;
  - preserves partial files on interruption so the next attempt resumes
    instead of restarting;
  - deletes and re-fetches once on a checksum failure, and only then
    surfaces an error that says what actually happened.

### Model catalogue — languages restored, duplicates gone, dead links fixed

- **The starter Whisper download 401'd for everyone.** The quantized
  tiny/base/small/medium/large rows pointed at a mirror repo that had
  gone private, so the onboarding "Download and continue" — the very
  first thing a new install does — failed with an authentication error.
  Every quantized Whisper row now points at the public
  `ggerganov/whisper.cpp` files (tiny/base/small ship as q5_1, the
  quant that repo actually hosts); rows with no public source were
  dropped. Verified live: a fresh install now onboards, downloads
  Whisper Base (q5_1), and transcribes.

- **Languages were never in the shipped catalogue.** The converter that
  bakes `assets/models/catalog.json` used a regex that never matched
  Dart list literals, so the `languages` field was dropped for every
  entry and the language dropdown had nothing to filter on. Languages
  now survive the round trip and the asset is re-baked with every voice
  tagged.
- **Duplicate rows suppressed.** `vibevoice-voice-emma` was
  byte-identical to `en-Emma_woman`; it is removed from the catalogue,
  skipped at probe and bake time, and a copy already on disk is renamed
  once. A further **29 same-file dual-name rows** are suppressed when
  the bundled catalogue, the live HuggingFace probe and the on-disk scan
  are merged, with the curated name winning.
- **One alphabet for language codes.** Voice codes are normalised to
  ISO 639-1 (`jp` → `ja`, `kr` → `ko`, `sp` → `es`, `in` → `en`), so the
  voice filter chips and the language dropdown finally match. The chips
  also render as "German (de)" rather than a bare code.

### Onboarding — the app opens with what you just downloaded

Onboarding's TTS recommendation now persists `defaultTtsModel` and
`defaultTtsVoice`, and the Synthesize screen prefers them (then the
selected model's own companion voices) over the first entry in catalogue
order. The reported behaviour — "downloads 1 voice and plays another" —
was exactly that fallback.

### Navigation — no screen is a dead end

Onboarding used `go()` to land the user on a destination with an empty
navigation stack, so there was nothing to pop and no back button
anywhere. Onboarding now lands with Home beneath the destination, and a
shared `rootAwareBackLeading()` gives every top-level screen a Home
button whenever nothing can be popped — which also covers arriving from
a shared file or a deep link.

### Voice cloning — the hand-off actually arrives

- `go('/synthesize')` re-uses the page already keyed to that path, so
  `initState` never ran again and the wizard's clip was dropped on the
  floor. The hand-off is applied in `didUpdateWidget` plus a direct
  provider seed.
- A banner on Synthesize names the reference clip that is in play.
- Clone attempts are pre-flighted with actionable messages (missing
  reference transcript, model cannot clone, unreadable clip) instead of
  a raw return code after the fact.
- The hand-off steers to a clone-capable model rather than leaving
  whatever was selected.
- Cloned output carries the **Art. 50(4) beep disclaimer** again —
  `customVoiceWavPath` was never passed to `writeWav`, so clones from a
  custom reference shipped unmarked.
- Non-WAV references are warned about at the picker, and non-ASCII
  reference paths on Windows are relocated before the engine sees them.

### Windows boot + argv

The stderr mirror now requires an actual terminal on Windows release
builds, disarms itself after the first failed write to a dead handle,
and guards the stdio done-futures — the uncaught `FileSystemException`
on every log line at boot is gone. Flags such as `--help` are filtered
out of the desktop argv intake with a pointer to the CLI, instead of
`Shared file does not exist: --help`.

### Command line

Seven fixes in `bin/crisperweaver.dart`:

- `vad` no longer opens the VAD model as a whisper context and then
  `whisper_free`s it (SIGABRT); it calls the free `crispasr_vad_slices`
  function, as the GUI does.
- `--vad` / `--vad-model` are honoured on `transcribe` — they were
  parsed and dropped. `--vad` now requires `--vad-model`, because a
  `dart run` entrypoint has no Flutter asset bundle to auto-detect it
  from.
- Numeric options validate up front and exit `64` with a usage message
  instead of a `FormatException` stack trace and exit `255`.
- `--chunk-ms 0` no longer loops forever.
- A missing input file is a usage error naming the path, not a failure
  deep inside the loader.
- `watermark` checks `--out` before running the embed rather than after.

### Advanced options

- Hover / help text on every decoding and diarisation control, localised
  in **en / de / zh**.
- The aligner override resolves catalogue keys instead of being silently
  inert, and marks entries that are `(Not downloaded)`.
- The diarisation method and the minimum / maximum speaker counts are
  wired through to the transcription paths — they were dead UI.

---

## Testing & verification

- **1500+ tests pass.** Nine new test files cover the fixes:
  `model_download_resume_test.dart`, `model_catalog_language_filter_test.dart`,
  `synthesize_defaults_test.dart`, `voice_clone_handoff_test.dart`,
  `root_aware_back_leading_test.dart`, `aligner_override_test.dart`,
  `diarization_wiring_test.dart`, `share_intake_args_test.dart`, plus
  CLI and log-service cases.
- **The download suite runs against a real localhost HTTP server** that
  serves partial content, mismatched ranges, `416`, short bodies and
  wrong checksums. The regression case reproduces the corruption on the
  old code, so the test proves the fix rather than restating it.
- **Full GUI drive on the Linux desktop build under Xvfb** with the real
  inference engine: onboarding through all four tasks, model filters,
  an interrupted and resumed download, the clone wizard hand-off, and
  back / home navigation on every top-level screen.
- **CLI baseline** re-run command by command against the previous
  behaviour.

---

## Notes

- Existing partial downloads from an older build are safe: the new
  engine validates the resume point with the server and starts over
  when it cannot be confirmed.
- A `vibevoice-voice-emma` file already in your models directory is
  renamed once, on first launch, to the name the catalogue keeps.
- `--vad` on the CLI now requires an explicit `--vad-model` path. The
  GUI is unaffected — it ships Silero as an asset.
- Known engine issue: the optional Silero LID model (a separate ~16 MB
  download; not the default) currently misidentifies languages on
  Linux x86_64 — tracked upstream in CrispASR. Whisper-based language
  detection, the default, is unaffected (en 0.977 on the reference
  clip).
