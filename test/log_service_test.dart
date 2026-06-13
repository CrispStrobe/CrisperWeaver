// LogService — LogEntry formatting, LogLevel ranking, ring buffer basics.

import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/services/log_service.dart';

void main() {
  group('LogLevel', () {
    test('rank ordering: trace < debug < info < warn < error', () {
      expect(LogLevel.trace.rank, lessThan(LogLevel.debug.rank));
      expect(LogLevel.debug.rank, lessThan(LogLevel.info.rank));
      expect(LogLevel.info.rank, lessThan(LogLevel.warn.rank));
      expect(LogLevel.warn.rank, lessThan(LogLevel.error.rank));
    });

    test('every level has a 3-char tag', () {
      for (final level in LogLevel.values) {
        expect(level.tag.length, 3, reason: '${level.name} tag');
      }
    });
  });

  group('LogEntry.format', () {
    test('basic format includes timestamp, level, tag, message', () {
      final entry = LogEntry(
        timestamp: DateTime(2026, 6, 13, 12, 0, 0),
        level: LogLevel.info,
        tag: 'test',
        message: 'hello world',
      );
      final formatted = entry.format();
      expect(formatted, contains('INF'));
      expect(formatted, contains('[test]'));
      expect(formatted, contains('hello world'));
      expect(formatted, contains('2026-06-13'));
    });

    test('error is appended when present', () {
      final entry = LogEntry(
        timestamp: DateTime(2026),
        level: LogLevel.error,
        tag: 'err',
        message: 'fail',
        error: Exception('boom'),
      );
      expect(entry.format(), contains('boom'));
    });

    test('structured fields are key=value pairs', () {
      final entry = LogEntry(
        timestamp: DateTime(2026),
        level: LogLevel.debug,
        tag: 'kv',
        message: 'with fields',
        fields: {'model': 'whisper-tiny', 'count': 42},
      );
      final formatted = entry.format();
      expect(formatted, contains('model=whisper-tiny'));
      expect(formatted, contains('count=42'));
    });

    test('field values with spaces are quoted', () {
      final entry = LogEntry(
        timestamp: DateTime(2026),
        level: LogLevel.debug,
        tag: 'kv',
        message: 'quoted',
        fields: {'path': '/my path/file.wav'},
      );
      expect(entry.format(), contains('path="/my path/file.wav"'));
    });

    test('stack trace included only when requested', () {
      final entry = LogEntry(
        timestamp: DateTime(2026),
        level: LogLevel.error,
        tag: 'err',
        message: 'trace test',
        stack: StackTrace.current,
      );
      expect(entry.format(includeStack: false), isNot(contains('#0')));
      expect(entry.format(includeStack: true), contains('#0'));
    });

    test('toString delegates to format', () {
      final entry = LogEntry(
        timestamp: DateTime(2026),
        level: LogLevel.info,
        tag: 't',
        message: 'msg',
      );
      expect(entry.toString(), entry.format());
    });
  });

  group('Log singleton', () {
    test('instance is stable', () {
      expect(Log.instance, same(Log.instance));
    });

    test('stream emits on log', () async {
      final entries = <LogEntry>[];
      final sub = Log.instance.stream.listen(entries.add);
      Log.instance.i('test', 'stream test');
      await Future<void>.delayed(Duration.zero);
      sub.cancel();
      expect(entries, isNotEmpty);
      expect(entries.last.message, 'stream test');
    });

    test('snapshot contains recent entries', () {
      Log.instance.i('test', 'snapshot test ${DateTime.now()}');
      final snap = Log.instance.snapshot();
      expect(snap, isNotEmpty);
      expect(snap.last.tag, 'test');
    });
  });
}
