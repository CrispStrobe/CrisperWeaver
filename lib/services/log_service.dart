import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/platform_utils.dart' as plat;

// Windows GUI builds detach from the console, so stderr's underlying
// handle is invalid (errno 6). `IOSink.writeln` enqueues the bytes
// synchronously but the actual write happens later in the event loop,
// where its FileSystemException escapes the sync try/catch and lands
// on platformDispatcher.onError as `[uncaught]` for every log line.
// `stdioType` returns `other` for most detached streams — but not all:
// issue #35 is a Windows 11 release build where `stdioType` reported
// something else and the deferred write still failed with
// `writeFrom failed, path = '' (OS Error: The handle is invalid,
// errno = 6)`. So on Windows release builds we require a *terminal*,
// which a double-clicked GUI process never has. The file sink and the
// in-app ring buffer capture everything either way.
bool _computeStderrUsable() {
  if (kIsWeb) return false;
  try {
    final type = stdioType(stderr);
    if (type == StdioType.other) return false;
    if (!kDebugMode && plat.isWindows) return type == StdioType.terminal;
    return true;
  } catch (_) {
    // Even touching `stderr` can throw where stdio is unavailable.
    return false;
  }
}

final bool _stderrUsable = _computeStderrUsable();

enum LogLevel { trace, debug, info, warn, error }

extension LogLevelX on LogLevel {
  /// Lower means more verbose.
  int get rank => LogLevel.values.indexOf(this);
  String get tag {
    switch (this) {
      case LogLevel.trace:
        return 'TRC';
      case LogLevel.debug:
        return 'DBG';
      case LogLevel.info:
        return 'INF';
      case LogLevel.warn:
        return 'WRN';
      case LogLevel.error:
        return 'ERR';
    }
  }
}

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;
  final Object? error;
  final StackTrace? stack;
  final Map<String, Object?>? fields; // structured k/v context

  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    this.error,
    this.stack,
    this.fields,
  });

  String format({bool includeStack = false}) {
    final ts = timestamp.toIso8601String();
    final errPart = error != null ? ' :: $error' : '';
    final kvPart = (fields == null || fields!.isEmpty)
        ? ''
        : ' ${fields!.entries.map((e) => '${e.key}=${_q(e.value)}').join(' ')}';
    final stackPart = (includeStack && stack != null) ? '\n$stack' : '';
    return '$ts ${level.tag} [$tag] $message$kvPart$errPart$stackPart';
  }

  static String _q(Object? v) {
    if (v == null) return 'null';
    final s = v.toString();
    if (s.contains(' ') || s.contains('"')) {
      return '"${s.replaceAll('"', r'\"')}"';
    }
    return s;
  }

  @override
  String toString() => format();
}

/// Process-wide ring-buffered logger.
///
/// The logger is intentionally a singleton — all services, engines, and
/// screens write through `Log.i('tag', 'message')`. It keeps the last N
/// entries in memory for the in-app Logs screen, and (when enabled) mirrors
/// every entry to `logs/session.log` inside the app documents directory.
class Log {
  Log._() {
    _armStdioDoneGuards();
  }
  static final Log _instance = Log._();
  static Log get instance => _instance;

  /// `IOSink.writeln` only *queues* bytes: a write that fails does so later,
  /// in the event loop, and the failure is delivered on `stdout`/`stderr`'s
  /// `done` future. With nobody listening it becomes an unhandled async
  /// error (`platformDispatcher.onError` / a zone handler). Attaching a
  /// no-op error handler is the documented way to neutralise a broken pipe
  /// and is safe on every platform with `dart:io` — `done` is an ordinary
  /// future, listening to it neither closes nor flushes the sink.
  static bool _stdioGuardsArmed = false;
  static void _ignoreStdioError(Object error, StackTrace stack) {}
  static void _armStdioDoneGuards() {
    if (kIsWeb || _stdioGuardsArmed) return;
    _stdioGuardsArmed = true;
    try {
      stderr.done.catchError(_ignoreStdioError);
      stdout.done.catchError(_ignoreStdioError);
    } catch (_) {
      // Some embedders don't expose stdio at all; nothing to guard then.
    }
  }

  /// True while log lines are still mirrored to the console.
  ///
  /// Starts from [_stderrUsable] and can be turned off for good by
  /// [disableConsoleMirror] when a console write is observed to fail.
  bool _consoleMirror = _stderrUsable || kDebugMode;
  bool get consoleMirrorEnabled => _consoleMirror;

  /// Does [error] look like a failed write to a dead console handle?
  ///
  /// The Windows GUI subsystem hands a detached process an invalid stdio
  /// handle; the queued write fails asynchronously with
  /// `FileSystemException: writeFrom failed, path = ''
  /// (OS Error: The handle is invalid, errno = 6)`. The empty path is what
  /// separates it from a genuine file-write failure.
  static bool isConsoleWriteFailure(Object? error) {
    if (error is StdoutException) return true;
    if (error is! FileSystemException) return false;
    final path = error.path;
    if (path != null && path.isNotEmpty) return false;
    final msg = error.message.toLowerCase();
    return msg.contains('writefrom') || msg.contains('write failed');
  }

  bool _consoleFailureNoted = false;

  /// Stop mirroring log lines to stderr/stdout for the rest of the process.
  ///
  /// Called from `main()`'s `platformDispatcher.onError` the first time a
  /// console write is seen to fail, so one broken handle cannot turn every
  /// subsequent log line into another uncaught error. Idempotent, and the
  /// one line it emits is written *after* the flag is cleared, so it can
  /// only reach the ring buffer, the stream, and the file sink — never the
  /// console that just failed.
  void disableConsoleMirror({String? reason}) {
    // Clear the flag first, unconditionally: the line below must not be able
    // to reach the console that just failed, and a second failure (from a
    // plugin's own `print`, say) must not add a second line.
    _consoleMirror = false;
    if (_consoleFailureNoted) return;
    _consoleFailureNoted = true;
    _emit(LogEntry(
      timestamp: DateTime.now(),
      level: LogLevel.info,
      tag: 'log',
      message: 'Console mirror disabled — this process has no writable '
          'console (log lines continue in the in-app Logs screen and the '
          'session log file)',
      fields: reason == null ? null : {'reason': reason},
    ));
  }

  final Queue<LogEntry> _buffer = Queue<LogEntry>();
  final StreamController<LogEntry> _stream =
      StreamController<LogEntry>.broadcast();

  int _capacity = 5000;
  LogLevel _minLevel = kDebugMode ? LogLevel.trace : LogLevel.info;
  bool _fileSink = false;
  File? _sinkFile;
  IOSink? _sink;

  /// Stream of newly-emitted entries.
  Stream<LogEntry> get stream => _stream.stream;

  /// A snapshot of the in-memory buffer (oldest first).
  List<LogEntry> snapshot() => _buffer.toList(growable: false);

  LogLevel get minLevel => _minLevel;
  bool get fileSinkEnabled => _fileSink;
  int get capacity => _capacity;
  File? get sinkFile => _sinkFile;

  void setMinLevel(LogLevel level) {
    _minLevel = level;
    // Re-emit as an info line so the UI can show the change.
    _emit(LogEntry(
      timestamp: DateTime.now(),
      level: LogLevel.info,
      tag: 'log',
      message: 'Log level set to ${level.tag}',
    ));
  }

  void setCapacity(int size) {
    _capacity = size.clamp(100, 100000);
    while (_buffer.length > _capacity) {
      _buffer.removeFirst();
    }
  }

  Future<void> enableFileSink(bool enable) async {
    if (enable == _fileSink) return;
    if (enable) {
      try {
        final dir = await getApplicationDocumentsDirectory();
        final logsDir = Directory(p.join(dir.path, 'logs'));
        if (!await logsDir.exists()) {
          await logsDir.create(recursive: true);
        }
        _sinkFile = File(p.join(logsDir.path, 'session.log'));
        _sink = _sinkFile!.openWrite(mode: FileMode.append);
        _fileSink = true;
        _emit(LogEntry(
          timestamp: DateTime.now(),
          level: LogLevel.info,
          tag: 'log',
          message: 'File sink enabled: ${_sinkFile!.path}',
        ));
      } catch (e, st) {
        _emit(LogEntry(
          timestamp: DateTime.now(),
          level: LogLevel.error,
          tag: 'log',
          message: 'Failed to open log sink',
          error: e,
          stack: st,
        ));
        _fileSink = false;
        _sink = null;
        _sinkFile = null;
      }
    } else {
      await _sink?.flush();
      await _sink?.close();
      _sink = null;
      _fileSink = false;
    }
  }

  Future<void> clear({bool alsoDisk = true}) async {
    _buffer.clear();
    if (alsoDisk && _sinkFile != null && await _sinkFile!.exists()) {
      await _sink?.flush();
      await _sink?.close();
      await _sinkFile!.writeAsString('');
      _sink = _sinkFile!.openWrite(mode: FileMode.append);
    }
    _emit(LogEntry(
      timestamp: DateTime.now(),
      level: LogLevel.info,
      tag: 'log',
      message: 'Log cleared',
    ));
  }

  void t(String tag, String message,
          {Object? error, StackTrace? stack, Map<String, Object?>? fields}) =>
      log(LogLevel.trace, tag, message,
          error: error, stack: stack, fields: fields);
  void d(String tag, String message,
          {Object? error, StackTrace? stack, Map<String, Object?>? fields}) =>
      log(LogLevel.debug, tag, message,
          error: error, stack: stack, fields: fields);
  void i(String tag, String message,
          {Object? error, StackTrace? stack, Map<String, Object?>? fields}) =>
      log(LogLevel.info, tag, message,
          error: error, stack: stack, fields: fields);
  void w(String tag, String message,
          {Object? error, StackTrace? stack, Map<String, Object?>? fields}) =>
      log(LogLevel.warn, tag, message,
          error: error, stack: stack, fields: fields);
  void e(String tag, String message,
          {Object? error, StackTrace? stack, Map<String, Object?>? fields}) =>
      log(LogLevel.error, tag, message,
          error: error, stack: stack, fields: fields);

  void log(
    LogLevel level,
    String tag,
    String message, {
    Object? error,
    StackTrace? stack,
    Map<String, Object?>? fields,
  }) {
    if (level.rank < _minLevel.rank) return;
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
      error: error,
      stack: stack,
      fields: fields,
    );
    _emit(entry);
  }

  /// Convenience for per-op timers — returns a closure that, on call,
  /// logs a single "done" line with ms elapsed + the caller's fields.
  /// Use:
  ///   final done = Log.instance.stopwatch('load-model', fields: {'name': n});
  ///   …work…
  ///   done(extra: {'bytes': size});
  void Function({Map<String, Object?>? extra, Object? error}) stopwatch(
    String tag, {
    String msg = 'done',
    Map<String, Object?>? fields,
    LogLevel level = LogLevel.info,
  }) {
    final start = DateTime.now();
    return ({extra, error}) {
      final ms = DateTime.now().difference(start).inMilliseconds;
      final merged = <String, Object?>{
        ...?fields,
        ...?extra,
        'ms': ms,
      };
      log(error != null ? LogLevel.error : level, tag, msg,
          fields: merged, error: error);
    };
  }

  // Rotation threshold — 5 MiB.
  static const int _rotateAtBytes = 5 * 1024 * 1024;
  int _sinkBytes = 0;

  void _emit(LogEntry entry) {
    _buffer.add(entry);
    while (_buffer.length > _capacity) {
      _buffer.removeFirst();
    }
    _stream.add(entry);
    final formatted = entry.format(includeStack: entry.stack != null);
    // Mirror to stderr so `flutter run` + standalone-launched apps
    // both surface it; debugPrint truncates at 800 chars in release,
    // stderr does not.
    // `_consoleMirror` also covers debugPrint: in a release build it falls
    // through to `print()`, i.e. the same stdout handle that is invalid in a
    // Windows GUI process.
    if (_consoleMirror) {
      if (kDebugMode) {
        debugPrint(formatted);
      } else if (_stderrUsable) {
        try {
          stderr.writeln(formatted);
        } catch (_) {}
      }
    }
    // Mirror to file sink when enabled.
    final sink = _sink;
    if (sink != null) {
      try {
        sink.writeln(formatted);
        _sinkBytes += formatted.length + 1;
        if (_sinkBytes > _rotateAtBytes) {
          unawaited(_rotate());
        }
      } catch (_) {
        // Swallow — don't crash the app over a log failure.
      }
    }
  }

  Future<void> _rotate() async {
    try {
      final sink = _sink;
      final file = _sinkFile;
      if (sink == null || file == null) return;
      await sink.flush();
      await sink.close();
      _sink = null;
      final rotated = File('${file.path}.1');
      if (await rotated.exists()) await rotated.delete();
      await file.rename(rotated.path);
      _sinkFile = File(file.path); // recreate pointer
      _sink = _sinkFile!.openWrite(mode: FileMode.append);
      _sinkBytes = 0;
      _emit(LogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.info,
        tag: 'log',
        message: 'Rotated session.log → session.log.1',
      ));
    } catch (e, st) {
      _emit(LogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.error,
        tag: 'log',
        message: 'Log rotation failed',
        error: e,
        stack: st,
      ));
    }
  }

  String dumpAll() {
    final buf = StringBuffer();
    for (final e in _buffer) {
      buf.writeln(e.format(includeStack: e.stack != null));
    }
    return buf.toString();
  }

  /// Dump a rich multi-line boot banner capturing platform / paths /
  /// sizes. Called once from main.dart after file sink init.
  Future<void> logBootBanner() async {
    final Map<String, String> info;
    if (kIsWeb) {
      info = {'platform': 'web'};
    } else {
      info = {
        'platform': plat.operatingSystem,
        'os_version': plat.operatingSystemVersion,
        'locale': plat.localeName,
        'cpu_cores': '${plat.numberOfProcessors}',
        'dart_version': plat.dartVersion,
        'cwd': Directory.current.path,
      };
    }
    try {
      final docs = await getApplicationDocumentsDirectory();
      info['docs_dir'] = docs.path;
    } catch (_) {}
    if (_sinkFile != null) info['log_file'] = _sinkFile!.path;
    _emit(LogEntry(
      timestamp: DateTime.now(),
      level: LogLevel.info,
      tag: 'boot',
      message: '============================================================',
    ));
    _emit(LogEntry(
      timestamp: DateTime.now(),
      level: LogLevel.info,
      tag: 'boot',
      message: 'CrisperWeaver session',
      fields: {...info},
    ));
  }

  /// Dumps the current buffer to a timestamped file and returns its path.
  Future<String> exportToFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final logsDir = Directory(p.join(dir.path, 'logs'));
    if (!await logsDir.exists()) {
      await logsDir.create(recursive: true);
    }
    final stamp =
        DateTime.now().toIso8601String().replaceAll(':', '').split('.').first;
    final file = File(p.join(logsDir.path, 'crisperweaver-$stamp.log'));
    await file.writeAsString(dumpAll(), encoding: utf8);
    return file.path;
  }
}
