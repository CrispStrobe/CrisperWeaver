// CrashBreadcrumb — the diagnostic that survives a native abort.
//
// The contract under test is narrow but load-bearing: a breadcrumb that is
// still on disk means the previous run died inside the operation it names,
// and one that was cleared means it did not. If clear() ever fails to run on
// a successful transcribe, every launch reports a crash that never happened
// and the signal is worthless.

import 'dart:convert';
import 'dart:io';

import 'package:crisper_weaver/services/crash_breadcrumb_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('breadcrumb');
    CrashBreadcrumb.resetForTest();
    CrashBreadcrumb.directoryForTest = tmp;
  });

  tearDown(() {
    CrashBreadcrumb.resetForTest();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  File breadcrumbFile() =>
      File('${tmp.path}/${CrashBreadcrumb.fileName}');

  NativeOperationRecord sampleOp() => NativeOperationRecord(
        phase: 'transcribe',
        startedAtUtc: DateTime.utc(2026, 8, 26, 4, 30),
        modelId: 'qwen3-asr-0.6b-q4_k',
        backend: 'qwen3',
        modelPath: '/Users/someone/models/qwen3-asr-0.6b-q4_k.gguf',
        modelBytes: 631026336,
        audioSeconds: 1804,
        physicalMemoryBytes: 16 * 1024 * 1024 * 1024,
        projectedBytes: 2 * 1024 * 1024 * 1024,
        platform: 'macos',
        extra: const {'vad': false},
      );

  test('record writes synchronously, so an abort cannot lose it', () {
    CrashBreadcrumb.record(sampleOp());
    // No await anywhere above — the bytes are on disk by the time record()
    // returns, which is the entire point.
    expect(breadcrumbFile().existsSync(), isTrue);
    final json = jsonDecode(breadcrumbFile().readAsStringSync()) as Map<String, Object?>;
    expect(json['phase'], 'transcribe');
    expect(json['model_id'], 'qwen3-asr-0.6b-q4_k');
    expect(json['audio_seconds'], 1804);
  });

  test('clear removes it, so a survivor means we really died', () {
    CrashBreadcrumb.record(sampleOp());
    expect(breadcrumbFile().existsSync(), isTrue);
    CrashBreadcrumb.clear();
    expect(breadcrumbFile().existsSync(), isFalse);
    expect(CrashBreadcrumb.takePending(), isNull);
  });

  test('takePending returns the record and consumes the file', () {
    CrashBreadcrumb.record(sampleOp());
    final pending = CrashBreadcrumb.takePending();
    expect(pending, isNotNull);
    expect(pending!.modelId, 'qwen3-asr-0.6b-q4_k');
    expect(pending.backend, 'qwen3');
    expect(pending.audioSeconds, 1804);
    expect(pending.extra['vad'], false);
    // Consumed — a stale crash re-reported at every launch trains the user
    // to ignore the one that matters.
    expect(breadcrumbFile().existsSync(), isFalse);
    expect(CrashBreadcrumb.takePending(), isNull);
  });

  test('the model path is reduced to a basename', () {
    // The report is meant to be pasted into a public issue. A home
    // directory is not the app's to disclose.
    CrashBreadcrumb.record(sampleOp());
    final raw = breadcrumbFile().readAsStringSync();
    expect(raw, isNot(contains('/Users/someone')));
    expect(raw, contains('qwen3-asr-0.6b-q4_k.gguf'));
  });

  test('a truncated file is dropped rather than reported as a guess', () {
    // The process dying mid-write is itself plausible; we just cannot say
    // what it died doing, so we must not invent it.
    breadcrumbFile().writeAsStringSync('{"phase": "transc');
    expect(CrashBreadcrumb.takePending(), isNull);
    expect(breadcrumbFile().existsSync(), isFalse);
  });

  test('an empty file is not a crash report', () {
    breadcrumbFile().writeAsStringSync('');
    expect(CrashBreadcrumb.takePending(), isNull);
  });

  test('consumePendingAtStartup exposes one record to every reader', () {
    CrashBreadcrumb.record(sampleOp());
    CrashBreadcrumb.consumePendingAtStartup();
    // Both the log line in main() and the diagnostics report read this,
    // so it must not be a one-shot that the first caller drains.
    expect(CrashBreadcrumb.pendingAtStartup, isNotNull);
    expect(CrashBreadcrumb.pendingAtStartup!.phase, 'transcribe');
    expect(CrashBreadcrumb.pendingAtStartup!.modelId, 'qwen3-asr-0.6b-q4_k');
    expect(breadcrumbFile().existsSync(), isFalse);
  });

  test('a clean previous run leaves nothing to report', () {
    CrashBreadcrumb.consumePendingAtStartup();
    expect(CrashBreadcrumb.pendingAtStartup, isNull);
  });

  test('describe names the things a maintainer would have to ask for', () {
    final text = sampleOp().describe();
    expect(text, contains('qwen3-asr-0.6b-q4_k'));
    expect(text, contains('1804.0 s'));
    expect(text, contains('16.0 GB'));
    expect(text, contains('transcribe'));
  });

  test('an unresolved directory makes every entry point a no-op', () {
    // Startup on a sandboxed platform can fail to resolve the documents
    // directory. That must not throw from inside a transcribe.
    CrashBreadcrumb.resetForTest();
    expect(() => CrashBreadcrumb.record(sampleOp()), returnsNormally);
    expect(() => CrashBreadcrumb.clear(), returnsNormally);
    expect(CrashBreadcrumb.takePending(), isNull);
  });
}
