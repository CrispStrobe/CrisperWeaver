import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'log_service.dart';

/// §5.25.8 — Watch-folder / scheduled transcription.
///
/// Monitors a user-configured directory for new audio files and notifies
/// listeners when a stable (write-complete) audio file appears. The caller
/// (typically the batch queue) enqueues it for transcription.
///
/// Desktop-only — mobile platforms lack background filesystem watch
/// capability without a foreground service.
class WatchFolderService {
  WatchFolderService({required this.onNewFile});

  /// Callback fired when a new audio file is detected and stable.
  final void Function(String path) onNewFile;

  /// Supported audio extensions (lowercase, with dot).
  static const _audioExtensions = {
    '.wav', '.mp3', '.flac', '.m4a', '.ogg', '.aac', '.opus', '.wma',
  };

  String? _watchPath;
  StreamSubscription<FileSystemEvent>? _watchSub;
  final _pendingFiles = <String, Timer>{};

  /// Whether the service is currently watching a folder.
  bool get isWatching => _watchSub != null;

  /// The currently watched path, or null.
  String? get watchPath => _watchPath;

  /// Start watching [dirPath]. Replaces any existing watch.
  void start(String dirPath) {
    stop();
    final dir = Directory(dirPath);
    if (!dir.existsSync()) {
      LogService.instance.log('WatchFolder: directory does not exist: $dirPath');
      return;
    }
    _watchPath = dirPath;
    _watchSub = dir.watch(events: FileSystemEvent.create).listen(_onEvent);
    LogService.instance.log('WatchFolder: watching $dirPath');
  }

  /// Stop watching.
  void stop() {
    _watchSub?.cancel();
    _watchSub = null;
    _watchPath = null;
    for (final timer in _pendingFiles.values) {
      timer.cancel();
    }
    _pendingFiles.clear();
  }

  void _onEvent(FileSystemEvent event) {
    if (event is! FileSystemCreateEvent) return;
    final path = event.path;
    final ext = p.extension(path).toLowerCase();
    if (!_audioExtensions.contains(ext)) return;

    // Debounce: wait 2 seconds of no further writes before notifying.
    // This handles files that are still being written (e.g., by a
    // recorder app or a download manager).
    _pendingFiles[path]?.cancel();
    _pendingFiles[path] = Timer(const Duration(seconds: 2), () {
      _pendingFiles.remove(path);
      final file = File(path);
      if (file.existsSync() && file.lengthSync() > 0) {
        LogService.instance.log('WatchFolder: new audio file: $path');
        onNewFile(path);
      }
    });
  }

  /// Dispose resources.
  void dispose() {
    stop();
  }
}
