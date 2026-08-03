// EU AI Act compliance tripwires — an allow-list over the call sites where
// the app's compliance controls have to be applied.
//
// WHY THIS FILE EXISTS
//
// Six compliance audits have each found at least one live defect, and every
// one of them had the same shape: a control implemented at the place a
// feature was designed, and a *second route* to the same capability that
// skipped it.
//
//   1. GUI marked generated audio; the CLI wrote bare WAVs.
//   2. The app marked generated text; the edit path re-encoded it away.
//   3. /v1/translations disclosed; /v1/audio/transcriptions did not.
//   4. Everything marked at production; `HistoryEntry.toJson` dropped it on save.
//   5. `CrispasrEngine` stripped emotion tags; `HfSpaceEngine` did not.
//   6. `CrispasrEngine` held all three controls; `TranscriptionWorkerPool`
//      — a second entry to the same native sessions — held none, and the
//      Copy/Share exits held none either.
//
// Each was fixed at the missing site, and each fix came with a test asserting
// *that site* was covered. None of those tests could see the next one. The
// round-6 test is the sharpest example: it asserted every **engine** parsing
// model text calls `EmotionInference.strip`, passed throughout, and a worker
// pool is not an engine.
//
// So this file does not test behaviour. It enumerates every call site in
// `lib/` that touches a compliance boundary and compares it against a
// reviewed list. A new site fails CI with a note saying what to check. The
// question stops being "did anyone remember?" and becomes a build break.
//
// WHEN THIS TEST FAILS
//
// It is not telling you the code is wrong. It is telling you that a call site
// appeared or moved at a boundary where six audits found defects, and that
// someone should spend thirty seconds deciding which of these is true:
//
//   • the new site is correctly routed through the control → update the count
//     here, in the same commit;
//   • the new site bypasses the control → route it, then update the count.
//
// Do not "fix" a failure by deleting the entry. Counting is deliberately
// brittle: brittleness is the mechanism, and the cost of a look is seconds.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Count non-overlapping occurrences of [needles] across every `.dart` file
/// under `lib/`, keyed by repo-relative path. Localisation output is excluded:
/// it is generated, and it holds no compliance logic.
Map<String, int> _scanLib(List<RegExp> needles) {
  final counts = <String, int>{};
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final rel = entity.path.replaceAll(r'\', '/');
    if (rel.startsWith('lib/l10n/')) continue;
    final src = entity.readAsStringSync();
    var n = 0;
    for (final needle in needles) {
      n += needle.allMatches(src).length;
    }
    if (n > 0) counts[rel] = n;
  }
  return counts;
}

void _expectAllowlist(
  Map<String, int> actual,
  Map<String, int> reviewed,
  String what,
  String todo,
) {
  final newFiles = actual.keys.toSet().difference(reviewed.keys.toSet());
  expect(newFiles, isEmpty,
      reason: '\n\nNEW $what in files not on the reviewed list:\n'
          '  ${newFiles.join('\n  ')}\n\n$todo\n');

  final gone = reviewed.keys.toSet().difference(actual.keys.toSet());
  expect(gone, isEmpty,
      reason: '\n\nReviewed $what disappeared from:\n  ${gone.join('\n  ')}\n\n'
          'If the code was deleted or moved, remove/relocate the entry here in '
          'the same commit so the list keeps describing the codebase.\n');

  for (final entry in reviewed.entries) {
    expect(actual[entry.key], entry.value,
        reason: '\n\n${entry.key}: expected ${entry.value} $what, '
            'found ${actual[entry.key]}.\n\n$todo\n');
  }
}

void main() {
  // -----------------------------------------------------------------------
  // Boundary 1 — content exits (Art. 50(2))
  //
  // Every point where text leaves the app without a file to carry a notice.
  // Round 6 found five of these bare while the Export control beside each of
  // them marked the same bytes, and while the Art. 50(1) first-use notice
  // promised in three languages that copied text carries a disclosure.
  // -----------------------------------------------------------------------
  test('every content exit is reviewed (Art. 50(2))', () {
    _expectAllowlist(
      _scanLib([RegExp(r'Clipboard\.setData'), RegExp(r'ShareParams\(')]),
      const {
        // Transcript text — routed through FileUtils.withDisclosure.
        'lib/screens/history_screen.dart': 1,
        'lib/screens/transcription_screen.dart': 2,
        'lib/widgets/transcription_output_widget.dart': 3,
        // Already-disclosed generated text: OCR, LLM summary, translation.
        'lib/widgets/summarize_dialog.dart': 1,
        'lib/screens/translate_screen.dart': 1,
        // Files on disk, marked before they were written.
        'lib/utils/file_utils.dart': 2,
        'lib/screens/synthesize_screen.dart': 1,
        // Not transcript content: diagnostics and build info.
        'lib/screens/logs_screen.dart': 3,
        'lib/screens/settings_screen.dart': 1,
      },
      'content exit(s)',
      'A content exit hands text or a file to the OS. If it can carry\n'
          'transcript, OCR, summary, translation or audio-Q&A output, it must\n'
          'route through FileUtils.withDisclosure (or attach an AiTextDisclosure\n'
          'string directly). See AI_ACT_RISK.md §5.2.',
    );
  });

  // -----------------------------------------------------------------------
  // Boundary 2 — model-text parse sites (Annex III 1(c))
  //
  // Any code that builds a segment from text a model produced has to drop
  // emotion tags first. Round 5 found `HfSpaceEngine` doing it untouched
  // (latent); round 6 found `workerSegmentFromMap` doing it on the pooled
  // path, which is the default for batch (live).
  // -----------------------------------------------------------------------
  test('no engine builds a segment from model text by hand (Annex III 1(c))',
      () {
    // Since 2026-08-03 the filter lives on the destination type
    // (`TranscriptionSegment.fromModelText`) rather than on any source, so
    // the engines and the worker — the only code that sees raw model output —
    // must not reach the plain constructor for it.
    //
    // Re-baselined when the factory landed. The previous version of this test
    // counted raw constructions per file and fired on the refactor, which is
    // what it is for: `crispasr_engine.dart` went 8 → 3 + 5 factory calls, and
    // four of those five had been building segments from model text with no
    // filter at all — the streamed-segment drain, the whisper mapper, and both
    // halves of the streaming controller.
    _expectAllowlist(
      _scanLib([RegExp(r'TranscriptionSegment\.fromModelText\(')]),
      const {
        'lib/engines/crispasr_engine.dart': 5,
        'lib/engines/hfspace_engine.dart': 2,
        'lib/services/transcription_worker.dart': 1,
        // The factory itself.
        'lib/engines/transcription_engine.dart': 1,
      },
      'model-text segment construction(s)',
      'A site that builds a segment from text a MODEL produced must use\n'
          'TranscriptionSegment.fromModelText, which strips emotion tags. The\n'
          'plain constructor is for segments that are already filtered —\n'
          'offset shifts, punctuation restoration, history reloads.\n'
          'See AI_ACT_RISK.md §2.8.',
    );

    _expectAllowlist(
      _scanLib([RegExp(r'TranscriptionSegment\(')]),
      const {
        // Re-map already-filtered segments: offset shift, pool remap.
        'lib/engines/crispasr_engine.dart': 3,
        // The factory's own delegation, plus copyWith and GeneratedKind.
        'lib/engines/transcription_engine.dart': 3,
        'lib/engines/mock_engine.dart': 1,
        'lib/main.dart': 1,
        'lib/services/aligner_service.dart': 1,
        'lib/services/batch_persistence_service.dart': 1,
        'lib/services/diarization_service.dart': 2,
        'lib/services/history_service.dart': 1,
        'lib/services/multilingual_transcription_service.dart': 1,
        'lib/services/punc_service.dart': 3,
        'lib/services/server_service.dart': 1,
        'lib/services/transcription_service.dart': 2,
        'lib/widgets/transcription_output_widget.dart': 1,
        // Parse user-supplied subtitle files, not model output.
        'lib/utils/transcript_parsers.dart': 2,
      },
      'raw segment construction(s)',
      'If this site builds a segment from text a MODEL produced, switch it to\n'
          'TranscriptionSegment.fromModelText. If it only rebuilds segments that\n'
          'were already filtered, it is fine — update the count.\n'
          'See AI_ACT_RISK.md §2.8.',
    );
  });

  // -----------------------------------------------------------------------
  // Boundary 3 — ask-prompt entry (Art. 5(1)(f), Annex III 1(c))
  //
  // A free-text question handed to an instruct-tuned audio model. Round 4
  // put the guard in `CrispasrEngine`; round 6 found the screen dispatching
  // to the worker pool directly, so batch jobs ran unscreened.
  // -----------------------------------------------------------------------
  test('setAsk is reachable only with a screened prompt (Art. 5(1)(f))', () {
    // The prompt-side equivalent of `fromModelText`. `session.setAsk` takes
    // `.value` off a `ScreenedAskPrompt`, which can only be built by
    // `ScreenedAskPrompt.screen` — so a new entry point cannot forget the
    // guard, it can only fail to compile.
    //
    // This assertion covers the case the type cannot: someone passing a bare
    // string, which still compiles because `setAsk` is upstream API typed on
    // String.
    for (final dir in const ['lib', 'bin']) {
      for (final entity in Directory(dir).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final rel = entity.path.replaceAll(r'\', '/');
        // The web stub declares the signature; it drives no model.
        if (rel == 'lib/native/crispasr_stub.dart') continue;
        final src = entity.readAsStringSync();
        for (final m in RegExp(r'\.setAsk\(([^)]*)\)').allMatches(src)) {
          final arg = m.group(1)!.trim();
          expect(arg, contains('screenedAsk'),
              reason: '\n\n$rel calls setAsk with `$arg`.\n\n'
                  'Only a ScreenedAskPrompt may reach the model. Build one\n'
                  'with ScreenedAskPrompt.screen(raw) and pass `.value`.\n'
                  'An LLM asked for a speaker\'s tone is an emotion\n'
                  'recognition system under Art. 3(39); no output filter can\n'
                  'catch free prose. See AI_ACT_RISK.md §2.9.\n');
        }
      }
    }
  });

  test('every ask-prompt entry point is reviewed (Art. 5(1)(f))', () {
    _expectAllowlist(
      _scanLib([RegExp(r'setAsk\(|askPrompt:')]),
      const {
        // Guarded: AffectivePromptGuard.offendingTerm before the model sees it.
        'lib/engines/crispasr_engine.dart': 3,
        'lib/services/transcription_worker_pool.dart': 1,
        'lib/services/server_service.dart': 1,
        // Downstream of a guarded caller.
        'lib/services/transcription_worker.dart': 1,
        // Plumbing: options, presets, UI field, web stub.
        'lib/screens/transcription_screen.dart': 4,
        'lib/widgets/advanced_options_widget.dart': 3,
        'lib/services/transcription_service.dart': 3,
        'lib/services/preset_service.dart': 1,
        'lib/native/crispasr_stub.dart': 1,
        // The guard itself.
        'lib/utils/affective_prompt_guard.dart': 1,
      },
      'ask-prompt reference(s)',
      'If this site can hand a free-text prompt to a model, it must first call\n'
          'AffectivePromptGuard.offendingTerm and refuse on a hit. An LLM asked\n'
          "for a speaker's tone is an emotion recognition system under\n"
          'Art. 3(39), and no output filter can catch free prose.\n'
          'See AI_ACT_RISK.md §2.9.',
    );
  });

  // -----------------------------------------------------------------------
  // Boundary 4 — the controls themselves must not become unreachable.
  // -----------------------------------------------------------------------
  test('the emotion filter is an allow-list, not a deny-list', () {
    // A deny-list ships any label it has not been told about. This assertion
    // is the difference between "no emotion recognition" holding by
    // construction and holding only until a backend adds a tag.
    final src = File('lib/utils/emotion_inference.dart').readAsStringSync();
    expect(src, contains('if (!isEventTag(tag)) continue;'),
        reason: 'strip() must keep only known acoustic events. Reverting to '
            '"drop known emotions, keep the rest" re-opens Annex III 1(c) for '
            'every affective label nobody has enumerated yet.');
  });
}
