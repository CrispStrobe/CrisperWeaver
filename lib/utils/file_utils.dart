import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../constants/app_constants.dart';
import '../engines/transcription_engine.dart';
import 'ai_text_disclosure.dart';

class FileUtils {
  /// EU AI Act Art. 50(2) — the notice text for [segments].
  ///
  /// Transcripts and audio-Q&A answers both leave through these exporters
  /// but are not the same artefact, and until the audit of 2026-08-03 every
  /// format called both "AI-generated synthetic speech". A model-authored
  /// answer described as a record of speech is mismarked, not marked: a
  /// reader who trusts the label reads assertions about the audio as
  /// quotations from it.
  static String disclosureFor(List<TranscriptionSegment> segments) =>
      segments.any((s) => s.isGenerated)
          ? AiTextDisclosure.audioQa
          : 'This content contains AI-generated synthetic speech.';

  /// Whether [segments] hold generated prose rather than transcribed speech
  /// — the case where even a plain-text export has to carry a mark, since
  /// there is no surrounding UI to supply the provenance.
  static bool _isGenerated(List<TranscriptionSegment> segments) =>
      segments.any((s) => s.isGenerated);

  static const String transcriptionsFolder = 'transcriptions';
  static const String modelsFolder = 'models';
  static const String audioFolder = 'audio';
  static const String cacheFolder = 'cache';

  /// Get the app's documents directory
  static Future<Directory> getAppDocumentsDirectory() async {
    return await getApplicationDocumentsDirectory();
  }

  /// Get the app's cache directory
  static Future<Directory> getAppCacheDirectory() async {
    return await getTemporaryDirectory();
  }

  /// Create a directory if it doesn't exist
  static Future<Directory> ensureDirectoryExists(String dirPath) async {
    final directory = Directory(dirPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  /// Get an arbitrary subdirectory under app documents.
  static Future<Directory> getDocumentsSubdir(String name) async {
    final appDir = await getAppDocumentsDirectory();
    final sub = path.join(appDir.path, name);
    return await ensureDirectoryExists(sub);
  }

  /// Get transcriptions directory
  static Future<Directory> getTranscriptionsDirectory() async {
    final appDir = await getAppDocumentsDirectory();
    final transcriptionsDir = path.join(appDir.path, transcriptionsFolder);
    return await ensureDirectoryExists(transcriptionsDir);
  }

  /// Get models directory
  static Future<Directory> getModelsDirectory() async {
    final appDir = await getAppDocumentsDirectory();
    final modelsDir = path.join(appDir.path, modelsFolder);
    return await ensureDirectoryExists(modelsDir);
  }

  /// Get audio directory
  static Future<Directory> getAudioDirectory() async {
    final appDir = await getAppDocumentsDirectory();
    final audioDir = path.join(appDir.path, audioFolder);
    return await ensureDirectoryExists(audioDir);
  }

  /// Get cache directory
  static Future<Directory> getCacheDirectory() async {
    final cacheDir = await getAppCacheDirectory();
    final appCacheDir = path.join(cacheDir.path, cacheFolder);
    return await ensureDirectoryExists(appCacheDir);
  }

  /// Generate unique filename with timestamp
  static String generateUniqueFilename(String baseName, String extension) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final sanitizedBaseName = sanitizeFilename(baseName);
    return '$sanitizedBaseName-$timestamp.$extension';
  }

  /// Sanitize filename by removing invalid characters
  static String sanitizeFilename(String filename) {
    // Remove or replace invalid characters
    return filename
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'_{2,}'), '_')
        .trim();
  }

  /// Save transcription to file.
  ///
  /// When [syntheticDisclosure] is true, formats that support it
  /// (SRT, VTT, JSON, Markdown) prepend an AI-generated content
  /// notice — required by EU AI Act Art. 50 when the transcript
  /// originates from or contains synthetic speech. Defaults to
  /// true: callers must explicitly opt out rather than opt in.
  static Future<File> saveTranscription(
    String text,
    String fileName, {
    TranscriptFormat format = TranscriptFormat.txt,
    List<TranscriptionSegment>? segments,
    bool syntheticDisclosure = true,
  }) async {
    final transcriptionsDir = await getTranscriptionsDirectory();
    final extension = _getExtensionForFormat(format);
    final safeFileName = sanitizeFilename(fileName);
    final filePath =
        path.join(transcriptionsDir.path, '$safeFileName.$extension');

    final file = File(filePath);

    String content;
    switch (format) {
      case TranscriptFormat.txt:
        // Plain transcription of real speech carries no mark — Art. 50(2)
        // reaches synthetic content, and a transcript is a record of what a
        // person actually said. Audio-Q&A output is not that: it is model-
        // authored prose, and `.txt` is the one format with no structure to
        // hide a notice in, so it has to go in the body.
        content = (syntheticDisclosure && _isGenerated(segments ?? []))
            ? AiTextDisclosure.forAudioQa(text)
            : text;
        break;
      case TranscriptFormat.srt:
        content = generateSrtContent(segments ?? [],
            syntheticDisclosure: syntheticDisclosure);
        break;
      case TranscriptFormat.vtt:
        content = generateVttContent(segments ?? [],
            syntheticDisclosure: syntheticDisclosure);
        break;
      case TranscriptFormat.json:
        content = generateJsonContent(segments ?? [],
            syntheticDisclosure: syntheticDisclosure);
        break;
      case TranscriptFormat.csv:
        content = generateCsvContent(segments ?? []);
        break;
      case TranscriptFormat.lrc:
        content = generateLrcContent(segments ?? []);
        break;
      case TranscriptFormat.wts:
        content = generateWtsContent(segments ?? []);
        break;
      case TranscriptFormat.md:
        content = generateMarkdownContent(segments ?? [],
            plainText: text, syntheticDisclosure: syntheticDisclosure);
        break;
    }

    // CSV / LRC / WTS have no notice slot of their own and carry no mark for
    // an ordinary transcript. Generated prose still has to be marked in
    // whatever format it leaves in, so it gets a leading comment line in the
    // syntax each format tolerates — `#` for the WTS shell script, a bare
    // first line for CSV, and an LRC `[re:]` metadata tag.
    if (syntheticDisclosure && _isGenerated(segments ?? [])) {
      const notice = AiTextDisclosure.audioQa;
      switch (format) {
        case TranscriptFormat.csv:
          content = '# $notice\n$content';
          break;
        case TranscriptFormat.wts:
          content = '# $notice\n$content';
          break;
        case TranscriptFormat.lrc:
          content = '[re:$notice]\n$content';
          break;
        default:
          break;
      }
    }

    await file.writeAsString(content, encoding: utf8);
    return file;
  }

  /// Save audio data to file
  static Future<File> saveAudioData(
    Uint8List audioData,
    String fileName, {
    String extension = 'wav',
  }) async {
    final audioDir = await getAudioDirectory();
    final safeFileName = sanitizeFilename(fileName);
    final filePath = path.join(audioDir.path, '$safeFileName.$extension');

    final file = File(filePath);
    await file.writeAsBytes(audioData);
    return file;
  }

  /// Read file as bytes
  static Future<Uint8List> readFileAsBytes(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File not found', filePath);
    }
    return await file.readAsBytes();
  }

  /// Read file as string
  static Future<String> readFileAsString(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File not found', filePath);
    }
    return await file.readAsString(encoding: utf8);
  }

  /// Copy file to another location
  static Future<File> copyFile(
      String sourcePath, String destinationPath) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw FileSystemException('Source file not found', sourcePath);
    }
    final destinationDir = Directory(path.dirname(destinationPath));
    await destinationDir.create(recursive: true);
    return await sourceFile.copy(destinationPath);
  }

  /// Move file to another location
  static Future<File> moveFile(
      String sourcePath, String destinationPath) async {
    final sourceFile = File(sourcePath);

    if (!await sourceFile.exists()) {
      throw FileSystemException('Source file not found', sourcePath);
    }

    // Ensure destination directory exists
    final destinationDir = Directory(path.dirname(destinationPath));
    await destinationDir.create(recursive: true);

    return await sourceFile.rename(destinationPath);
  }

  /// Delete file
  static Future<bool> deleteFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Get file size
  static Future<int> getFileSize(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return 0;
    }
    return await file.length();
  }

  /// Get file modification date
  static Future<DateTime> getFileModificationDate(String filePath) async {
    final file = File(filePath);
    final stat = await file.stat();
    return stat.modified;
  }

  /// List files in directory
  static Future<List<FileInfo>> listFilesInDirectory(
    String directoryPath, {
    List<String>? extensions,
    bool recursive = false,
  }) async {
    final directory = Directory(directoryPath);
    if (!await directory.exists()) {
      return [];
    }

    final files = <FileInfo>[];
    final entities =
        recursive ? directory.list(recursive: true) : directory.list();

    await for (final entity in entities) {
      if (entity is File) {
        final extension = path.extension(entity.path).toLowerCase();

        if (extensions == null || extensions.contains(extension)) {
          final stat = await entity.stat();
          files.add(FileInfo(
            path: entity.path,
            name: path.basename(entity.path),
            size: stat.size,
            modified: stat.modified,
            extension: extension,
          ));
        }
      }
    }

    return files;
  }

  /// Get all transcription files
  static Future<List<FileInfo>> getTranscriptionFiles() async {
    final transcriptionsDir = await getTranscriptionsDirectory();
    return await listFilesInDirectory(
      transcriptionsDir.path,
      extensions: ['.txt', '.srt', '.vtt', '.json'],
    );
  }

  /// Get all audio files
  static Future<List<FileInfo>> getAudioFiles() async {
    final audioDir = await getAudioDirectory();
    return await listFilesInDirectory(
      audioDir.path,
      extensions: AppConstants.supportedAudioExtensions,
    );
  }

  /// Share file
  static Future<void> shareFile(String filePath, {String? subject}) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File not found', filePath);
    }

    await SharePlus.instance.share(ShareParams(
      files: [XFile(filePath)],
      subject: subject ?? path.basename(filePath),
    ));
  }

  /// Share the audio file and a chosen-format transcript as a
  /// two-attachment bundle. The recipient gets both files in one
  /// message — useful for sending a recording + its captions to
  /// a colleague, or archiving in email.
  ///
  /// Writes the transcript to a temp file (in the standard
  /// transcriptions directory) so it has a real path on disk
  /// for SharePlus to wrap as an XFile. Returns the transcript
  /// file path so callers can show "saved to …" in a snackbar.
  static Future<String> shareAudioAndTranscript({
    required String audioPath,
    required List<TranscriptionSegment> segments,
    required String plainText,
    TranscriptFormat transcriptFormat = TranscriptFormat.srt,
    String? subject,
  }) async {
    final audio = File(audioPath);
    if (!await audio.exists()) {
      throw FileSystemException('Audio file not found', audioPath);
    }
    final baseName =
        'transcript-${DateTime.now().millisecondsSinceEpoch}';
    final transcript = await saveTranscription(
      plainText,
      baseName,
      format: transcriptFormat,
      segments: segments,
    );
    await SharePlus.instance.share(ShareParams(
      files: [XFile(audioPath), XFile(transcript.path)],
      subject: subject ?? path.basenameWithoutExtension(audioPath),
    ));
    return transcript.path;
  }

  /// Clear cache directory
  static Future<void> clearCache() async {
    final cacheDir = await getCacheDirectory();
    if (await cacheDir.exists()) {
      await for (final entity in cacheDir.list()) {
        if (entity is File) {
          await entity.delete();
        } else if (entity is Directory) {
          await entity.delete(recursive: true);
        }
      }
    }
  }

  /// Get total size of directory
  static Future<int> getDirectorySize(String directoryPath) async {
    final directory = Directory(directoryPath);
    if (!await directory.exists()) {
      return 0;
    }

    int totalSize = 0;
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File) {
        final stat = await entity.stat();
        totalSize += stat.size;
      }
    }

    return totalSize;
  }

  /// Get app storage usage
  static Future<StorageUsage> getStorageUsage() async {
    final documentsDir = await getAppDocumentsDirectory();
    final cacheDir = await getAppCacheDirectory();

    final transcriptionsSize = await getDirectorySize(
        path.join(documentsDir.path, transcriptionsFolder));
    final modelsSize =
        await getDirectorySize(path.join(documentsDir.path, modelsFolder));
    final audioSize =
        await getDirectorySize(path.join(documentsDir.path, audioFolder));
    final cacheSize = await getDirectorySize(cacheDir.path);

    return StorageUsage(
      transcriptions: transcriptionsSize,
      models: modelsSize,
      audio: audioSize,
      cache: cacheSize,
    );
  }

  // Private helper methods
  static String _getExtensionForFormat(TranscriptFormat format) {
    switch (format) {
      case TranscriptFormat.txt:
        return 'txt';
      case TranscriptFormat.srt:
        return 'srt';
      case TranscriptFormat.vtt:
        return 'vtt';
      case TranscriptFormat.json:
        return 'json';
      case TranscriptFormat.csv:
        return 'csv';
      case TranscriptFormat.lrc:
        return 'lrc';
      case TranscriptFormat.wts:
        return 'wts';
      case TranscriptFormat.md:
        return 'md';
    }
  }

  static String generateSrtContent(
    List<TranscriptionSegment> segments, {
    bool syntheticDisclosure = true,
  }) {
    final buffer = StringBuffer();
    if (syntheticDisclosure) {
      // SRT has no comment syntax — `NOTE` is WebVTT's, and a bare line
      // before cue 1 is a parse error or a swallowed disclosure depending
      // on the player. Emitting the notice as a real cue at 00:00:00 is the
      // only way it reliably reaches a human watching the subtitles.
      buffer.writeln('0');
      buffer.writeln('00:00:00,000 --> 00:00:03,000');
      buffer.writeln(disclosureFor(segments));
      buffer.writeln();
    }
    for (int i = 0; i < segments.length; i++) {
      final segment = segments[i];
      buffer.writeln('${i + 1}');
      buffer.writeln(
          '${formatSrtTime(segment.startTime)} --> ${formatSrtTime(segment.endTime)}');
      buffer.writeln('${segment.speaker ?? ''}: ${segment.text}');
      buffer.writeln();
    }
    return buffer.toString();
  }

  static String generateVttContent(
    List<TranscriptionSegment> segments, {
    bool syntheticDisclosure = true,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('WEBVTT');
    if (syntheticDisclosure) {
      buffer.writeln();
      buffer.writeln('NOTE ${disclosureFor(segments)}');
    }
    buffer.writeln();

    for (int i = 0; i < segments.length; i++) {
      final segment = segments[i];
      buffer.writeln('${i + 1}');
      buffer.writeln(
          '${formatVttTime(segment.startTime)} --> ${formatVttTime(segment.endTime)}');
      buffer.writeln('${segment.speaker ?? ''}: ${segment.text}');
      buffer.writeln();
    }
    return buffer.toString();
  }

  static String generateJsonContent(
    List<TranscriptionSegment> segments, {
    bool syntheticDisclosure = true,
  }) {
    final segList = segments
        .map((segment) => {
              'text': segment.text,
              'startTime': segment.startTime,
              'endTime': segment.endTime,
              'speaker': segment.speaker,
              'confidence': segment.confidence,
            })
        .toList();

    if (!syntheticDisclosure) {
      return const JsonEncoder.withIndent('  ').convert(segList);
    }
    return const JsonEncoder.withIndent('  ').convert({
      '_disclosure': disclosureFor(segments),
      if (_isGenerated(segments)) '_content': 'audio-qa-answer',
      'segments': segList,
    });
  }

  static String formatSrtTime(double seconds) {
    final hours = (seconds / 3600).floor();
    final minutes = ((seconds % 3600) / 60).floor();
    final secs = seconds % 60;
    final ms = ((secs % 1) * 1000).round();

    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${secs.floor().toString().padLeft(2, '0')},'
        '${ms.toString().padLeft(3, '0')}';
  }

  static String formatVttTime(double seconds) {
    final hours = (seconds / 3600).floor();
    final minutes = ((seconds % 3600) / 60).floor();
    final secs = seconds % 60;
    final ms = ((secs % 1) * 1000).round();

    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${secs.floor().toString().padLeft(2, '0')}.'
        '${ms.toString().padLeft(3, '0')}';
  }

  /// CSV: one row per segment. Column order matches CrispASR's
  /// `crispasr -o csv` output (start_s, end_s, speaker, text). Standard
  /// RFC-4180 quoting — embedded `"` is doubled, newlines stay verbatim.
  static String generateCsvContent(List<TranscriptionSegment> segments) {
    final buffer = StringBuffer();
    buffer.writeln('start_s,end_s,speaker,text');
    for (final s in segments) {
      buffer.writeln(
          '${s.startTime.toStringAsFixed(3)},${s.endTime.toStringAsFixed(3)},${_csvCell(s.speaker ?? '')},${_csvCell(s.text)}');
    }
    return buffer.toString();
  }

  static String _csvCell(String s) {
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  /// LRC lyrics: `[mm:ss.xx]text` per segment. Compatible with most
  /// karaoke players; speaker labels embedded inline (`Speaker 1: …`).
  static String generateLrcContent(List<TranscriptionSegment> segments) {
    final buffer = StringBuffer();
    buffer.writeln('[ti:CrisperWeaver transcription]');
    buffer.writeln('[length:${formatLrcTime(segments.isEmpty ? 0 : segments.last.endTime)}]');
    for (final s in segments) {
      final tag = '[${formatLrcTime(s.startTime)}]';
      final speaker = s.speaker == null ? '' : '${s.speaker}: ';
      buffer.writeln('$tag$speaker${s.text.trim()}');
    }
    return buffer.toString();
  }

  /// LRC time stamp: `mm:ss.xx`. Truncates at 99:59.99 (matches the
  /// historical 2-digit-minute convention).
  static String formatLrcTime(double seconds) {
    final minutes = (seconds / 60).floor();
    final secs = seconds % 60;
    final cs = ((secs - secs.floor()) * 100).round();
    return '${minutes.toString().padLeft(2, '0')}:'
        '${secs.floor().toString().padLeft(2, '0')}.'
        '${cs.toString().padLeft(2, '0')}';
  }

  /// WTS (Whisper Text Segments) — CrispASR's debug-friendly format
  /// mirroring `crispasr -o wts`. One line per segment with both
  /// timestamp forms and the optional speaker label.
  static String generateWtsContent(List<TranscriptionSegment> segments) {
    final buffer = StringBuffer();
    for (final s in segments) {
      final t0 = formatSrtTime(s.startTime);
      final t1 = formatSrtTime(s.endTime);
      final spk = s.speaker == null ? '' : '<${s.speaker}> ';
      buffer.writeln('[$t0 --> $t1] $spk${s.text.trim()}');
    }
    return buffer.toString();
  }

  /// Markdown — bullet-list with timestamps + bold speaker
  /// labels, ready to paste into Slack / Discord / Notion /
  /// GitHub. Falls back to [plainText] (a single paragraph) when
  /// no segments are available — keeps the format usable even
  /// when the caller has only `currentTranscription` to hand.
  static String generateMarkdownContent(
    List<TranscriptionSegment> segments, {
    String plainText = '',
    bool syntheticDisclosure = true,
  }) {
    final buffer = StringBuffer();
    buffer.writeln(_isGenerated(segments) ? '# AI-generated answer' : '# Transcript');
    buffer.writeln();
    if (syntheticDisclosure) {
      buffer.writeln('> **Notice:** ${disclosureFor(segments)}');
      buffer.writeln();
    }
    if (segments.isEmpty) {
      if (plainText.isNotEmpty) buffer.writeln(plainText);
      return buffer.toString();
    }
    for (final s in segments) {
      // Strip millis from the timestamp — for a chat-message
      // context, `00:01:23` reads better than `00:01:23,456`.
      final t0 = formatSrtTime(s.startTime).split(',').first;
      final t1 = formatSrtTime(s.endTime).split(',').first;
      final speaker = (s.speaker ?? '').trim();
      final speakerMd = speaker.isEmpty ? '' : '**$speaker**: ';
      buffer.writeln('- `$t0 → $t1` $speakerMd${s.text.trim()}');
    }
    return buffer.toString();
  }
}

enum TranscriptFormat {
  txt,
  srt,
  vtt,
  json,
  csv,
  lrc,
  wts,
  /// Markdown — verbatim transcript laid out as a bulleted list
  /// with timestamps and speaker labels. Renders beautifully in
  /// Slack / Discord / Notion / GitHub gists, which is the
  /// common "share to chat" destination.
  md,
}

class FileInfo {
  final String path;
  final String name;
  final int size;
  final DateTime modified;
  final String extension;

  const FileInfo({
    required this.path,
    required this.name,
    required this.size,
    required this.modified,
    required this.extension,
  });

  String get formattedSize {
    if (size < 1024) {
      return '$size B';
    } else if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }

  String get formattedDate {
    return '${modified.day}/${modified.month}/${modified.year}';
  }
}

class StorageUsage {
  final int transcriptions;
  final int models;
  final int audio;
  final int cache;

  const StorageUsage({
    required this.transcriptions,
    required this.models,
    required this.audio,
    required this.cache,
  });

  int get total => transcriptions + models + audio + cache;

  String formatSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }

  String get formattedTranscriptions => formatSize(transcriptions);
  String get formattedModels => formatSize(models);
  String get formattedAudio => formatSize(audio);
  String get formattedCache => formatSize(cache);
  String get formattedTotal => formatSize(total);
}
