import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../engines/transcription_engine.dart';
import 'audio_fingerprint_service.dart';

/// A single saved transcription, shown in the history screen.
class HistoryEntry {
  final String id;
  final DateTime createdAt;
  final String? sourcePath;
  final String? sourceUrl;
  final String engineId;
  final String? modelId;
  final String? language;
  final bool diarizationEnabled;
  final Duration processingTime;
  final List<TranscriptionSegment> segments;
  /// User-chosen speaker labels keyed by the diariser's original label
  /// (e.g. "Speaker 1" → "Alice"). Applied at render time so segments
  /// stay portable. Empty when no renames were made.
  final Map<String, String> speakerNames;

  /// §5.25.11 — Audio file fingerprint for deduplication. Computed once
  /// on save; checked by the batch queue to detect re-imports.
  final String? audioFingerprint;

  const HistoryEntry({
    required this.id,
    required this.createdAt,
    required this.engineId,
    required this.segments,
    this.sourcePath,
    this.sourceUrl,
    this.modelId,
    this.language,
    this.diarizationEnabled = false,
    this.processingTime = Duration.zero,
    this.speakerNames = const {},
    this.audioFingerprint,
  });

  String get title {
    if (sourcePath != null) return p.basename(sourcePath!);
    if (sourceUrl != null) return sourceUrl!;
    return 'Recording ${createdAt.toIso8601String()}';
  }

  String get fullText => segments.map((s) => s.text).join(' ').trim();

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'sourcePath': sourcePath,
        'sourceUrl': sourceUrl,
        'engineId': engineId,
        'modelId': modelId,
        'language': language,
        'diarizationEnabled': diarizationEnabled,
        'processingTimeMs': processingTime.inMilliseconds,
        // Field added 2026-05; older history files omit it and the
        // loader treats absent as empty so back-compat is automatic.
        'speakerNames': speakerNames,
        if (audioFingerprint != null) 'audioFingerprint': audioFingerprint,
        'segments': segments
            .map((s) => {
                  'text': s.text,
                  'startTime': s.startTime,
                  'endTime': s.endTime,
                  'speaker': s.speaker,
                  'confidence': s.confidence,
                  if (s.tags.isNotEmpty) 'tags': s.tags,
                })
            .toList(),
      };

  static HistoryEntry fromJson(Map<String, dynamic> j) => HistoryEntry(
        id: j['id'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        sourcePath: j['sourcePath'] as String?,
        sourceUrl: j['sourceUrl'] as String?,
        engineId: j['engineId'] as String,
        modelId: j['modelId'] as String?,
        language: j['language'] as String?,
        diarizationEnabled: j['diarizationEnabled'] as bool? ?? false,
        processingTime: Duration(
          milliseconds: (j['processingTimeMs'] as num?)?.toInt() ?? 0,
        ),
        speakerNames: ((j['speakerNames'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k.toString(), v.toString())),
        audioFingerprint: j['audioFingerprint'] as String?,
        segments: ((j['segments'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map((m) => TranscriptionSegment(
                  text: m['text'] as String? ?? '',
                  startTime: (m['startTime'] as num?)?.toDouble() ?? 0.0,
                  endTime: (m['endTime'] as num?)?.toDouble() ?? 0.0,
                  speaker: m['speaker'] as String?,
                  confidence: (m['confidence'] as num?)?.toDouble() ?? 1.0,
                  tags: ((m['tags'] as List?) ?? const []).cast<String>(),
                ))
            .toList(),
      );
}

/// Persists [HistoryEntry] records as individual JSON files in the app's
/// documents directory so transcriptions survive across launches.
class HistoryService {
  static const _folder = 'history';
  final _uuid = const Uuid();

  Directory? _dir;

  /// Default constructor — uses path_provider to land entries under
  /// `<app-docs>/history/` like the production app.
  HistoryService();

  /// Test-only injection: skip path_provider and write entries
  /// straight into [dir]. Avoids the need for a path_provider mock
  /// in unit tests that just want to exercise save/load round-trips.
  @visibleForTesting
  HistoryService.withDirectory(Directory dir) : _dir = dir;

  Future<Directory> _ensureDir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, _folder));
    if (!await dir.exists()) await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  /// §5.25.7 — load a single entry by id for comparison/review.
  /// Returns null if the file doesn't exist or is corrupt.
  Future<HistoryEntry?> loadEntry(String id) async {
    final dir = await _ensureDir();
    final file = File(p.join(dir.path, '$id.json'));
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return HistoryEntry.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// §5.1.3 — overwrite an existing entry by id. Used when the
  /// user inline-edits a segment text after the entry was first
  /// saved. The entry's `createdAt` / `engineId` / `modelId`
  /// stay untouched; only segments + speakerNames are typically
  /// changed. No-op when the file doesn't exist (we don't
  /// resurrect deleted entries — caller should fall back to
  /// `save(...)` for that case).
  Future<void> update(HistoryEntry entry) async {
    final dir = await _ensureDir();
    final file = File(p.join(dir.path, '${entry.id}.json'));
    if (!await file.exists()) return;
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(entry.toJson()),
    );
  }

  Future<HistoryEntry> save({
    required String engineId,
    required List<TranscriptionSegment> segments,
    String? sourcePath,
    String? sourceUrl,
    String? modelId,
    String? language,
    bool diarizationEnabled = false,
    Duration processingTime = Duration.zero,
    Map<String, String> speakerNames = const {},
    String? audioFingerprint,
  }) async {
    final dir = await _ensureDir();
    // §5.25.11 — Compute file fingerprint if a source path is provided
    // and no explicit fingerprint was passed.
    String? fp = audioFingerprint;
    if (fp == null && sourcePath != null) {
      try {
        fp = await AudioFingerprintService.computeFileFingerprint(sourcePath);
      } catch (_) {
        // Non-critical — dedup just won't catch this file.
      }
    }
    final entry = HistoryEntry(
      id: _uuid.v4(),
      createdAt: DateTime.now(),
      engineId: engineId,
      segments: segments,
      sourcePath: sourcePath,
      sourceUrl: sourceUrl,
      modelId: modelId,
      language: language,
      diarizationEnabled: diarizationEnabled,
      processingTime: processingTime,
      speakerNames: speakerNames,
      audioFingerprint: fp,
    );
    final file = File(p.join(dir.path, '${entry.id}.json'));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(entry.toJson()),
    );
    return entry;
  }

  Future<List<HistoryEntry>> list() async {
    final dir = await _ensureDir();
    final entries = <HistoryEntry>[];
    await for (final ent in dir.list()) {
      if (ent is File && ent.path.endsWith('.json')) {
        try {
          final json = jsonDecode(await ent.readAsString());
          entries.add(HistoryEntry.fromJson(json as Map<String, dynamic>));
        } catch (_) {
          // Skip corrupt entries rather than crashing history list.
        }
      }
    }
    entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return entries;
  }

  Future<void> delete(String id) async {
    final dir = await _ensureDir();
    final file = File(p.join(dir.path, '$id.json'));
    if (await file.exists()) await file.delete();
  }

  Future<void> clear() async {
    final dir = await _ensureDir();
    if (await dir.exists()) {
      await for (final ent in dir.list()) {
        if (ent is File) await ent.delete();
      }
    }
  }
}
