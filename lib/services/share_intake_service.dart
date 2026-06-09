import 'dart:async';
import 'dart:io';

import '../utils/platform_utils.dart' as plat;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../main.dart';
import '../utils/audio_utils.dart';
import '../utils/transcript_parsers.dart';
import 'batch_queue_service.dart';
import 'log_service.dart';

/// Listens for files shared *into* the app — via the OS share sheet
/// (Android), "Open In…" from other apps (iOS), `.desktop` argv
/// intake (Linux), and drag-and-drop onto the Dock icon (macOS) —
/// and routes them through a single triage path:
///   - first usable audio file → [selectedAudioPathProvider]
///   - remaining audio files → batch queue
///   - transcript files (.srt / .vtt / .txt) → AppState review mode
///
/// Entry points:
///   - [start] — wires up the [ReceiveSharingIntent] stream on
///     Android + iOS. No-op on desktop (the plugin doesn't ship
///     a desktop implementation).
///   - [acceptPaths] — public hook for desktop argv intake.
///     `main()` collects argv and calls this once the provider
///     graph is up.
///
/// iOS requires a separate Share Extension target (Xcode work
/// the `flutter create` template does not generate automatically)
/// to receive arbitrary files from the share sheet. What we get
/// for free is the document-type-based "Open In…" handoff
/// already declared in Info.plist.
class ShareIntakeService {
  ShareIntakeService(this._ref);
  final Ref _ref;

  StreamSubscription<List<SharedMediaFile>>? _streamSub;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    // `receive_sharing_intent` only implements Android and iOS. Calling it
    // on desktop platforms just throws `MissingPluginException` — skip it
    // and rely on macOS/Linux/Windows document-type handoff instead.
    if (!(plat.isIOS || plat.isAndroid)) {
      Log.instance.d('share',
          'Share intake not supported on ${plat.operatingSystem}; skipping');
      return;
    }

    // Files that arrived while the app was suspended.
    try {
      final initial = await ReceiveSharingIntent.instance.getInitialMedia();
      _handleBatch(initial);
    } catch (e, st) {
      Log.instance
          .w('share', 'Initial media fetch failed', error: e, stack: st);
    }

    // Files that arrive while the app is running.
    _streamSub = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen(_handleBatch, onError: (Object e, StackTrace st) {
      Log.instance.w('share', 'Share stream error', error: e, stack: st);
    });
  }

  void _handleBatch(List<SharedMediaFile> files) {
    if (files.isEmpty) return;
    // Triage: split the batch by content type.
    //   - First usable audio file → selectedAudioPathProvider.
    //     The UI shows a single source at a time.
    //   - Subsequent audio files → batch queue (don't silently
    //     drop a multi-file share from Files / Voice Memos).
    //   - Any transcript file (.srt / .vtt / .txt) → "review
    //     mode" — parse + load into AppState so the user can
    //     view + edit a previously-saved transcript even when
    //     they don't have the source audio handy.
    String? firstSelected;
    var queuedCount = 0;
    String? firstTranscriptPath;
    for (final f in files) {
      final path = f.path;
      if (path.isEmpty) continue;
      if (!File(path).existsSync()) {
        Log.instance.w('share', 'Shared file does not exist: $path');
        continue;
      }
      if (AudioUtils.isSupportedAudioFile(path)) {
        if (firstSelected == null) {
          firstSelected = path;
          Log.instance.i('share', 'Ingested shared audio: $path');
          _ref.read(selectedAudioPathProvider.notifier).state = path;
        } else {
          _ref.read(batchQueueProvider.notifier).enqueue(path);
          queuedCount++;
        }
        continue;
      }
      if (TranscriptParsers.isSupportedTranscript(path)) {
        // Defer the actual parse-and-load to after the loop —
        // the user can only see one transcript at a time, so we
        // take the first one and discard later transcripts in
        // the same batch (rare in practice).
        firstTranscriptPath ??= path;
        continue;
      }
      Log.instance.d('share', 'Ignoring unrecognised share: $path');
    }
    if (queuedCount > 0) {
      Log.instance.i('share',
          'Enqueued $queuedCount additional file(s) into the batch queue');
    }
    if (firstTranscriptPath != null && firstSelected == null) {
      // Only fire the transcript-load path when no audio share
      // arrived in the same batch — otherwise the audio takes
      // precedence (the user is more likely to want to
      // transcribe the audio than overlay a separate transcript).
      // ignore: discarded_futures
      _loadTranscript(firstTranscriptPath);
    }
  }

  /// Parse a transcript file and hand the segments to AppState
  /// as "review mode". Fire-and-forget — the parse runs on the
  /// calling isolate, but SRT / VTT files are small enough that
  /// the parse completes in single-digit ms.
  Future<void> _loadTranscript(String filePath) async {
    final parsed = await TranscriptParsers.parseFile(filePath);
    if (parsed == null) {
      Log.instance.w('share', 'Transcript parse failed: $filePath');
      return;
    }
    Log.instance.i('share',
        'Loaded ${parsed.source.name} transcript with ${parsed.segments.length} segment(s)',
        fields: {'file': filePath});
    _ref
        .read(appStateProvider.notifier)
        .completeTranscription(parsed.segments);
    if (parsed.segments.isEmpty && parsed.plainText.isNotEmpty) {
      // Plaintext drop — no segments, just the flat dump.
      // completeTranscription with empty segments wipes the
      // current text; restore it from the parsed plaintext so
      // the user sees something on screen.
      _ref
          .read(appStateProvider.notifier)
          .replaceLiveStreamingText(parsed.plainText);
    }
  }

  /// Public entry-point for desktop-platform argv intake.
  /// Linux's .desktop file passes `%F` as positional args; the
  /// main() bootstrap reads those at launch and calls this
  /// method. Cross-platform-safe — paths that don't exist or
  /// don't match a known shape get logged + dropped, same as
  /// the share-intent pipeline.
  ///
  /// Synthesises `SharedMediaFile` shells so it reuses the
  /// existing triage code (`_handleBatch`) verbatim — keeps the
  /// audio/transcript split logic in one place.
  void acceptPaths(List<String> paths) {
    if (paths.isEmpty) return;
    final files = <SharedMediaFile>[];
    for (final p in paths) {
      if (p.trim().isEmpty) continue;
      files.add(SharedMediaFile(
        path: p,
        type: SharedMediaType.file,
      ));
    }
    if (files.isEmpty) return;
    Log.instance
        .i('share', 'Accepted ${files.length} argv path(s) on desktop');
    _handleBatch(files);
  }

  Future<void> dispose() async {
    await _streamSub?.cancel();
    _streamSub = null;
  }
}

/// Riverpod provider: call `.start()` once at app boot.
final shareIntakeServiceProvider = Provider<ShareIntakeService>((ref) {
  final svc = ShareIntakeService(ref);
  ref.onDispose(svc.dispose);
  return svc;
});
