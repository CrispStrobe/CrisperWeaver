// Widget test for the §5.8 alt-token tap-to-pick popover in the
// transcript editor.
//
// PLAN §5.8 noted this as the one missing test for the alt-token
// feature: "The transcript-editor edit dialog uses Riverpod providers +
// AppLocalizations, both of which need scaffolding to pump headlessly.
// Unit + preset round-trip tests cover the data plumbing; the UI test is
// a nice-to-have." This fills it.
//
// Flow under test (transcription_output_widget.dart):
//   segment overflow (⋯) → "Edit" → edit dialog renders an
//   "Alternative candidates" chip row for any word carrying `alts` →
//   tapping a chip opens a PopupMenu of the runner-up candidates →
//   selecting one rewrites the first occurrence of the word in the
//   edit TextField.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/engines/transcription_engine.dart';
import 'package:crisper_weaver/l10n/generated/app_localizations.dart';
import 'package:crisper_weaver/widgets/transcription_output_widget.dart';

Widget _host(List<TranscriptionSegment> segments) {
  return ProviderScope(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: TranscriptionOutputWidget(segments: segments),
      ),
    ),
  );
}

void main() {
  // One segment whose first word "kubectl" carries two runner-up
  // candidates. The alt text intentionally has a leading space (whisper
  // sub-word BPE marker) to exercise the leading-space strip on both the
  // chip label and the replacement.
  final segments = <TranscriptionSegment>[
    const TranscriptionSegment(
      text: 'kubectl apply now',
      startTime: 0.0,
      endTime: 1.5,
      words: [
        TranscriptionWord(
          word: 'kubectl',
          startTime: 0.0,
          endTime: 0.6,
          confidence: 0.4,
          alts: [
            TranscriptionWordAlt(text: ' cubicle', p: 0.034),
            TranscriptionWordAlt(text: ' cube', p: 0.012),
          ],
        ),
        TranscriptionWord(
            word: ' apply', startTime: 0.6, endTime: 1.0, confidence: 0.9),
        TranscriptionWord(
            word: ' now', startTime: 1.0, endTime: 1.5, confidence: 0.9),
      ],
    ),
  ];

  Future<void> openEditDialog(WidgetTester tester) async {
    await tester.pumpWidget(_host(segments));
    await tester.pumpAndSettle();

    // Open the segment's overflow menu and pick "Edit".
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
  }

  testWidgets('edit dialog renders an alt-candidate chip for a word with alts',
      (tester) async {
    await openEditDialog(tester);

    // Dialog is up...
    expect(find.text('Edit segment'), findsOneWidget);
    // ...with the alt-suggestions block (only shown when a word has alts).
    expect(find.text('Alternative candidates'), findsOneWidget);
    // The chip shows the leading-space-stripped word.
    expect(find.widgetWithText(Chip, 'kubectl'), findsOneWidget);
  });

  testWidgets('a segment with no word alts shows no suggestions block',
      (tester) async {
    final plain = <TranscriptionSegment>[
      const TranscriptionSegment(
        text: 'kubectl apply now',
        startTime: 0.0,
        endTime: 1.5,
        words: [
          TranscriptionWord(
              word: 'kubectl', startTime: 0.0, endTime: 0.6, confidence: 0.4),
        ],
      ),
    ];
    await tester.pumpWidget(_host(plain));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Edit segment'), findsOneWidget);
    expect(find.text('Alternative candidates'), findsNothing);
  });

  testWidgets('picking an alt rewrites the first occurrence in the TextField',
      (tester) async {
    await openEditDialog(tester);

    // Tapping the chip opens the candidate PopupMenu.
    await tester.tap(find.widgetWithText(Chip, 'kubectl'));
    await tester.pumpAndSettle();

    // Both runner-ups are listed (leading space stripped on render),
    // each with its 1-dp probability.
    expect(find.text('cubicle'), findsOneWidget);
    expect(find.text('cube'), findsOneWidget);
    expect(find.text('3.4%'), findsOneWidget);
    expect(find.text('1.2%'), findsOneWidget);

    // Pick the top candidate.
    await tester.tap(find.text('cubicle'));
    await tester.pumpAndSettle();

    // The edit buffer now reads the swapped word; "apply now" is intact.
    expect(find.text('cubicle apply now'), findsOneWidget);
  });
}
