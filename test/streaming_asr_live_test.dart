// Live streaming-ASR test (PLAN §9.1 exemplar / streaming).
//
// Exercises the sliding-window streaming path the app's
// TranscriptionWorker mirrors — CrispASR.openStream(...) →
// StreamingSession.feed/flush/close (crispasr_stream_* in the C API).
// Tagged `slow` and self-skips when the dylib / tiny model are absent.
//
// HOW THE NATIVE STREAM BEHAVES (verified against CrispASR
// src/crispasr_c_api.cpp, the C entrypoints the binding wraps):
//
//   * crispasr_stream_open(ctx, n_threads, step_ms, length_ms, keep_ms,
//     language, translate) — opens a sliding-window decoder over an
//     already-loaded *whisper* ctx (lines 846-865). The binding's
//     CrispASR.openStream({stepMs, lengthMs, keepMs, nThreads, language,
//     translate}) (crispasr.dart ~1671) forwards exactly these.
//   * crispasr_stream_feed(s, pcm, n) appends `n` samples to an internal
//     accumulator (line 985). While accum < n_samples_step it returns 0
//     ("still buffering" — line 988-990) and the Dart binding's
//     StreamingSession.feed (crispasr.dart ~1804) maps that 0 → null.
//     Once a fed chunk pushes accum across step_ms it runs one decode and
//     returns 1 (line 992-994) → the binding pulls a StreamingUpdate via
//     crispasr_stream_get_text. So a chunk that does NOT cross stepMs
//     yields null; the chunk that crosses it yields an update.
//   * Each decode is single_segment + no_context (lines 910/916) and
//     get_text (line 997) returns ONLY the latest window's concatenated
//     text — it is OVERWRITTEN every decode, NOT appended. With a 10 s
//     window / 3 s step on the ~11 s JFK clip the windows overlap
//     heavily, but the "final" committed text is just the last window.
//     So this test accumulates the text of EVERY update (the rolling
//     commits) and asserts a JFK keyword appears somewhere across them —
//     robust against any single window revising its partial.
//   * crispasr_stream_flush(s) forces a decode of whatever is still
//     buffered (line 1043); returns 0 when accum is empty. The binding's
//     StreamingSession.flush (~1827) maps that to a StreamingUpdate-or-null.
//   * crispasr_stream_close(s) frees the native state — there is NO Dart
//     finalizer (binding doc ~1773), so the session is closed explicitly
//     here, and the underlying whisper ctx is disposed in tearDown.
//
// IMPORTANT (mirrors vad_live_test): CrispASR(modelPath) loads `modelPath`
// as a whisper ASR context, so we open it on the real tiny ASR model and
// dispose it in tearDown. The StreamingSession is created via openStream
// on that ctx and closed explicitly.
//
// Run:
//   scripts/run_live_tests.sh test/streaming_asr_live_test.dart

@Tags(['slow'])
library;

import 'dart:typed_data';

import 'package:crispasr/crispasr.dart' as crispasr;
import 'package:flutter_test/flutter_test.dart';

import 'support/crispasr_models.dart';

void main() {
  final lib = CrispModels.lib;
  final skip = CrispModels.skipReason(models: ['whisper_tiny']);

  group('Streaming ASR live', () {
    late crispasr.DecodedAudio audio;
    crispasr.CrispASR? cr;
    crispasr.StreamingSession? stream;

    setUp(() {
      if (skip != null) return;
      // jfk.wav is ~11 s of clear English speech — long enough to cross
      // several 3 s steps inside a 10 s rolling window.
      audio = crispasr.decodeAudioFile(
        CrispModels.fixture('jfk.wav'),
        libPath: lib,
      );
      // Open the ctx on a real ASR model so dispose() is safe.
      cr = crispasr.CrispASR(CrispModels.model('whisper_tiny')!, libPath: lib);
    });

    tearDown(() {
      // Close the stream first (no native finalizer), then the ctx.
      stream?.close();
      stream = null;
      cr?.dispose();
      cr = null;
    });

    test('decodes the fixture to 16 kHz mono PCM', () {
      expect(audio.sampleRate, 16000);
      expect(audio.samples.length, greaterThan(16000)); // > 1 s of audio
    }, skip: skip);

    test('feeds 1 s chunks and commits a transcript containing a JFK keyword',
        () {
      // CLI-default window: every 3 s of fresh audio decodes the last 10 s
      // with 200 ms of carried context — the same defaults openStream uses
      // and the app's streaming path relies on.
      stream = cr!.openStream(
        stepMs: 3000,
        lengthMs: 10000,
        keepMs: 200,
        language: 'en',
      );

      // Simulate real-time arrival: hand the PCM over in fixed 1 s
      // (16000-sample) chunks. Most chunks won't cross the 3 s step and
      // must return null; every 3rd-ish chunk triggers a decode.
      const chunk = 16000; // 1 s @ 16 kHz
      final pcm = audio.samples;
      final updates = <crispasr.StreamingUpdate>[];
      var nullCount = 0;

      for (var off = 0; off < pcm.length; off += chunk) {
        final end = (off + chunk) < pcm.length ? off + chunk : pcm.length;
        final slice = Float32List.sublistView(pcm, off, end);
        final u = stream!.feed(slice);
        if (u == null) {
          nullCount++;
        } else {
          updates.add(u);
        }
      }
      // Flush any tail audio still buffered below the step threshold so the
      // final partial is committed too.
      final tail = stream!.flush();
      if (tail != null) updates.add(tail);

      // At least one chunk must have NOT crossed the step (proves the
      // buffering/null contract is exercised, not just every-chunk decode).
      expect(nullCount, greaterThan(0),
          reason: 'sub-step chunks must return null while buffering');
      // At least one real decode must have happened.
      expect(updates, isNotEmpty,
          reason: 'streaming must produce at least one non-null update');

      // Each update is a rolling commit over an overlapping window; the
      // "final" committed text is just the last window. Assert on the
      // accumulation of all commits so a single window revising its
      // partial can't drop the keyword.
      final allCommitted =
          updates.map((u) => u.text).join(' ').toLowerCase();
      expect(allCommitted.trim(), isNotEmpty,
          reason: 'committed transcript must be non-empty');
      expect(
        allCommitted.contains('country') || allCommitted.contains('ask'),
        isTrue,
        reason: 'committed JFK transcript should contain "country" or "ask"; '
            'got: $allCommitted',
      );

      // The last update's window times must be non-negative and monotonic
      // (end >= start). We deliberately do NOT assert an upper bound: a
      // streaming window's reported t1 is relative to the rolling-buffer
      // clock, not the clip wall-clock, and can run well past the clip
      // duration — pinning a bound here is brittle and tests an
      // implementation detail, not correctness. The keyword assertion
      // above is the real signal that streaming decode worked.
      final last = updates.last;
      expect(last.start, greaterThanOrEqualTo(0));
      expect(last.end, greaterThanOrEqualTo(last.start));
    }, skip: skip);
  });
}
