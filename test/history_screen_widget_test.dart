// Widget tests for HistoryScreen — covers the §5.25.2 semantic search
// toggle and §5.25.7 compare picker button.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/engines/transcription_engine.dart';
import 'package:crisper_weaver/l10n/generated/app_localizations.dart';
import 'package:crisper_weaver/main.dart' show historyServiceProvider;
import 'package:crisper_weaver/screens/history_screen.dart';
import 'package:crisper_weaver/services/history_service.dart';
import 'package:crisper_weaver/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fake history service that returns in-memory entries without touching
/// the filesystem. Uses HistoryService.withDirectory with a temp dir
/// but overrides list() by just returning the canned entries.
class _FakeHistoryService extends HistoryService {
  final List<HistoryEntry> entries;

  _FakeHistoryService(this.entries)
      : super.withDirectory(Directory.systemTemp);

  @override
  Future<List<HistoryEntry>> list() async => entries;

  @override
  Future<void> delete(String id) async {
    entries.removeWhere((e) => e.id == id);
  }

  @override
  Future<void> clear() async => entries.clear();
}

Widget _host({
  required List<HistoryEntry> entries,
  required SettingsService settings,
}) {
  return ProviderScope(
    overrides: [
      historyServiceProvider.overrideWithValue(_FakeHistoryService(entries)),
      settingsServiceProvider.overrideWithValue(settings),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: HistoryScreen(),
    ),
  );
}

HistoryEntry _entry(String id, String text, {String? sourcePath}) =>
    HistoryEntry(
      id: id,
      createdAt: DateTime(2026, 1, 1),
      engineId: 'mock',
      sourcePath: sourcePath ?? 'file_$id.wav',
      segments: [
        TranscriptionSegment(
          text: text,
          startTime: 0,
          endTime: 10,
        ),
      ],
    );

late SettingsService _settings;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _settings = SettingsService(await SharedPreferences.getInstance());
  });

  group('Semantic search toggle (§5.25.2)', () {
    testWidgets('toggle icon is present in the search bar', (tester) async {
      await tester.pumpWidget(_host(settings: _settings, entries: [_entry('1', 'hello world')]));
      await tester.pumpAndSettle();

      // The toggle is an IconButton with either Icons.abc or Icons.psychology
      // Default state is substring search (Icons.abc)
      expect(find.byIcon(Icons.abc), findsOneWidget);
    });

    testWidgets('tapping toggle switches to semantic icon', (tester) async {
      await tester.pumpWidget(_host(settings: _settings, entries: [_entry('1', 'hello world')]));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.abc));
      await tester.pump();

      // After toggle, should show the semantic search icon
      expect(find.byIcon(Icons.psychology), findsOneWidget);
      expect(find.byIcon(Icons.abc), findsNothing);
    });

    testWidgets('tapping toggle twice returns to substring mode',
        (tester) async {
      await tester.pumpWidget(_host(settings: _settings, entries: [_entry('1', 'hello world')]));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.abc));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.psychology));
      await tester.pump();

      expect(find.byIcon(Icons.abc), findsOneWidget);
    });
  });

  group('History entry display', () {
    testWidgets('entries render their titles', (tester) async {
      await tester.pumpWidget(_host(settings: _settings, entries: [
        _entry('1', 'first entry text', sourcePath: 'interview.wav'),
        _entry('2', 'second entry text', sourcePath: 'meeting.wav'),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('interview.wav'), findsOneWidget);
      expect(find.text('meeting.wav'), findsOneWidget);
    });

    testWidgets('empty state shows empty message', (tester) async {
      await tester.pumpWidget(_host(settings: _settings, entries: []));
      await tester.pumpAndSettle();

      // Should show the empty history state widget
      expect(find.byIcon(Icons.history), findsOneWidget);
    });
  });

  group('Compare picker (§5.25.7)', () {
    testWidgets('compare button appears once advanced features are on',
        (tester) async {
      _settings.experimentalFeatures = true;
      await tester.pumpWidget(_host(settings: _settings, entries: [
        _entry('1', 'first entry'),
        _entry('2', 'second entry'),
      ]));
      await tester.pumpAndSettle();

      // Expand the first entry to reveal action buttons
      await tester.tap(find.text('file_1.wav'));
      await tester.pumpAndSettle();

      // The compare button should be visible
      expect(find.byIcon(Icons.compare_arrows), findsWidgets);
    });

    testWidgets('compare button is hidden in the default beta surface',
        (tester) async {
      // Comparing two transcripts presumes two finished runs of the same
      // audio, which a first-run tester does not have. Hidden until they
      // opt in — see SettingsService.experimentalFeatures.
      _settings.experimentalFeatures = false;
      await tester.pumpWidget(_host(settings: _settings, entries: [
        _entry('1', 'first entry'),
        _entry('2', 'second entry'),
      ]));
      await tester.pumpAndSettle();
      await tester.tap(find.text('file_1.wav'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.compare_arrows), findsNothing);
      // The neighbouring export/delete actions are untouched.
      expect(find.byIcon(Icons.delete_outline), findsWidgets);
    });
  });

  group('Search filtering', () {
    testWidgets('typing in search filters entries', (tester) async {
      await tester.pumpWidget(_host(settings: _settings, entries: [
        _entry('1', 'flutter is great', sourcePath: 'flutter_talk.wav'),
        _entry('2', 'dart is fast', sourcePath: 'dart_talk.wav'),
      ]));
      await tester.pumpAndSettle();

      // Both entries visible initially
      expect(find.text('flutter_talk.wav'), findsOneWidget);
      expect(find.text('dart_talk.wav'), findsOneWidget);

      // Type in search
      await tester.enterText(find.byType(TextField), 'flutter');
      await tester.pump();

      // Only flutter entry should remain
      expect(find.text('flutter_talk.wav'), findsOneWidget);
      expect(find.text('dart_talk.wav'), findsNothing);
    });
  });
}
