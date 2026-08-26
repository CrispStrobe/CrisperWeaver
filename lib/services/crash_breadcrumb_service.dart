// CrashBreadcrumb — the one diagnostic that survives a native abort.
//
// Every field report we cannot act on has the same shape. Issue #34:
// "No idea, as I cant provide any info since the entire windows UI freeze.
// No way to debug." Issue #33: a crash on two platforms with two different
// timings and nothing else. Issue #21: "Piper still crashes. No log."
//
// There is a structural reason for that. Transcription and synthesis run
// through FFI into libcrispasr, and a `GGML_ASSERT` failure there calls
// `abort()`. That takes the whole Flutter process down from inside native
// code: no Dart exception, no `runZonedGuarded`, no chance to write anything.
// The existing log file sink is an `IOSink`, so whatever it was holding is
// lost with it — and a memory-exhaustion freeze ends in a hard power cycle,
// which loses even more.
//
// So the breadcrumb is written BEFORE the call, synchronously, and deleted
// after the call returns. If it is still on disk at the next launch, the
// previous run died inside the operation it describes. That turns "no log"
// into an exact model, backend, quantisation, audio length and host RAM.
//
// Deliberately NOT built on `Log`: this must not share a buffer, an isolate,
// or a code path with anything that could itself be the thing that broke.
// One small synchronous write, no dependencies beyond `dart:io`.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// What the process was doing when it stopped existing.
class NativeOperationRecord {
  const NativeOperationRecord({
    required this.phase,
    required this.startedAtUtc,
    this.modelId,
    this.backend,
    this.modelPath,
    this.modelBytes,
    this.audioSeconds,
    this.physicalMemoryBytes,
    this.projectedBytes,
    this.appVersion,
    this.platform,
    this.extra = const <String, Object?>{},
  });

  /// `load`, `transcribe`, `synthesize`, … — coarse on purpose.
  final String phase;
  final DateTime startedAtUtc;
  final String? modelId;
  final String? backend;
  final String? modelPath;
  final int? modelBytes;
  final double? audioSeconds;
  final int? physicalMemoryBytes;
  final int? projectedBytes;
  final String? appVersion;
  final String? platform;
  final Map<String, Object?> extra;

  Map<String, Object?> toJson() => <String, Object?>{
        'phase': phase,
        'started_at_utc': startedAtUtc.toIso8601String(),
        if (modelId != null) 'model_id': modelId,
        if (backend != null) 'backend': backend,
        // Basename only — the full path leaks a home directory into a report
        // the user is about to paste into a public issue.
        if (modelPath != null && modelPath!.isNotEmpty)
          'model_file': p.basename(modelPath!),
        if (modelBytes != null) 'model_bytes': modelBytes,
        if (audioSeconds != null) 'audio_seconds': audioSeconds,
        if (physicalMemoryBytes != null)
          'physical_memory_bytes': physicalMemoryBytes,
        if (projectedBytes != null) 'projected_bytes': projectedBytes,
        if (appVersion != null) 'app_version': appVersion,
        if (platform != null) 'platform': platform,
        if (extra.isNotEmpty) 'extra': extra,
      };

  static NativeOperationRecord? fromJson(Map<String, Object?> json) {
    final phase = json['phase'];
    final started = json['started_at_utc'];
    if (phase is! String || started is! String) return null;
    final startedAt = DateTime.tryParse(started);
    if (startedAt == null) return null;
    return NativeOperationRecord(
      phase: phase,
      startedAtUtc: startedAt,
      modelId: json['model_id'] as String?,
      backend: json['backend'] as String?,
      modelPath: json['model_file'] as String?,
      modelBytes: (json['model_bytes'] as num?)?.toInt(),
      audioSeconds: (json['audio_seconds'] as num?)?.toDouble(),
      physicalMemoryBytes: (json['physical_memory_bytes'] as num?)?.toInt(),
      projectedBytes: (json['projected_bytes'] as num?)?.toInt(),
      appVersion: json['app_version'] as String?,
      platform: json['platform'] as String?,
      extra: (json['extra'] as Map?)?.cast<String, Object?>() ??
          const <String, Object?>{},
    );
  }

  /// Rendered into the diagnostics report and the issue-report template.
  String describe() {
    final b = StringBuffer()
      ..writeln('Interrupted during: $phase')
      ..writeln('Started (UTC): ${startedAtUtc.toIso8601String()}');
    if (modelId != null) b.writeln('Model: $modelId');
    if (backend != null) b.writeln('Backend: $backend');
    if (modelBytes != null) {
      b.writeln('Model size: ${(modelBytes! / (1024 * 1024)).round()} MB');
    }
    if (audioSeconds != null) {
      b.writeln('Audio length: ${audioSeconds!.toStringAsFixed(1)} s');
    }
    if (physicalMemoryBytes != null) {
      b.writeln('System RAM: '
          '${(physicalMemoryBytes! / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB');
    }
    if (projectedBytes != null) {
      b.writeln('Projected usage: '
          '${(projectedBytes! / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB');
    }
    if (appVersion != null) b.writeln('App: $appVersion');
    if (platform != null) b.writeln('Platform: $platform');
    for (final e in extra.entries) {
      b.writeln('${e.key}: ${e.value}');
    }
    return b.toString();
  }
}

/// Writes and reads the breadcrumb file. All disk access is synchronous:
/// an async write that has not reached the filesystem when `abort()` fires
/// is exactly the write we lose.
class CrashBreadcrumb {
  CrashBreadcrumb._();

  static const String fileName = 'last_native_op.json';

  static Directory? _dir;

  /// Resolved once at startup by [initialize]. Web has no filesystem and no
  /// FFI, so every entry point below no-ops there.
  static Future<void> initialize() async {
    if (kIsWeb) return;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'diagnostics'));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _dir = dir;
    } catch (_) {
      // A diagnostic that breaks startup is worse than no diagnostic.
      _dir = null;
    }
  }

  @visibleForTesting
  static set directoryForTest(Directory? dir) => _dir = dir;

  static File? get _file {
    final dir = _dir;
    return dir == null ? null : File(p.join(dir.path, fileName));
  }

  /// Record that we are about to enter native code. Best-effort: a failure
  /// here must never stop the transcription the user asked for.
  static void record(NativeOperationRecord op) {
    final f = _file;
    if (f == null) return;
    try {
      f.writeAsStringSync(jsonEncode(op.toJson()), flush: true);
    } catch (_) {
      // Read-only volume, sandbox denial, disk full. Nothing to do.
    }
  }

  /// Native code returned. Clearing is what makes a surviving file mean
  /// "we died in there" rather than "we were there once".
  static void clear() {
    final f = _file;
    if (f == null) return;
    try {
      if (f.existsSync()) f.deleteSync();
    } catch (_) {
      // Ignore.
    }
  }

  /// Read and remove a breadcrumb left by a previous run, if any.
  ///
  /// Removing it here is deliberate: a stale breadcrumb reported at every
  /// subsequent launch trains the user to ignore it. One report, then gone.
  static NativeOperationRecord? takePending() {
    final f = _file;
    if (f == null) return null;
    try {
      if (!f.existsSync()) return null;
      final raw = f.readAsStringSync();
      f.deleteSync();
      if (raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return NativeOperationRecord.fromJson(decoded.cast<String, Object?>());
    } catch (_) {
      // Truncated JSON is itself evidence — the process died mid-write — but
      // we cannot say what of, so drop it rather than report a guess.
      try {
        _file?.deleteSync();
      } catch (_) {}
      return null;
    }
  }

  /// Set by [consumePendingAtStartup] so the diagnostics report and the UI
  /// can both mention the same crash without racing to consume the file.
  static NativeOperationRecord? _pendingAtStartup;

  /// The breadcrumb this launch inherited from the previous run, or null.
  static NativeOperationRecord? get pendingAtStartup => _pendingAtStartup;

  /// Call once during bootstrap, after [initialize].
  static void consumePendingAtStartup() {
    _pendingAtStartup = takePending();
  }

  @visibleForTesting
  static void resetForTest() {
    _pendingAtStartup = null;
    _dir = null;
  }
}
