// AudioPrefetchService — §5.23 Q2 v1 pipeline parallelism.
//
// While the drain loop transcribes file N, we kick off the audio
// decode for file N+1 in a worker isolate. By the time the engine
// asks AudioService for file N+1's samples, the decode has already
// completed (or is well underway), so the GPU isn't waiting on
// disk + decode work.
//
// Why an isolate? The miniaudio FFI call inside
// `crispasr.decodeAudioFile` blocks the calling isolate for the
// duration of the decode — typically 50–500 ms per mp3/m4a/opus
// file. Running it on the main isolate would stall the UI thread
// (frame drops, unresponsive scroll). Isolate.run trades a small
// startup cost (~5 ms) for non-blocking parallelism.
//
// Memory shape: one in-flight Future per recently-seen path,
// keyed by absolute path. The drain loop calls `prefetch(path)` to
// kick off a decode; the AudioService then calls
// `consumePrefetched(path)` (or falls through to its synchronous
// decode if no entry is cached) and removes the entry — the
// samples are not held longer than necessary.
//
// Cross-platform: pure `Isolate.run` + the existing
// `crispasr.decodeAudioFile` FFI helper, which lazy-opens
// `libcrispasr` per isolate. Works identically on
// macOS/Linux/Windows/Android/iOS — every platform CrisperWeaver
// ships on already has the dynamic library available.

import 'dart:isolate';

import '../native/crispasr_import.dart' as crispasr;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'log_service.dart';

class AudioPrefetchService {
  AudioPrefetchService();

  /// In-flight + recently-completed decodes, keyed by absolute file
  /// path. Holding the Future (not the resolved DecodedAudio) lets
  /// callers `await` whether the work is mid-flight or already done,
  /// and one cache entry covers both cases.
  final Map<String, Future<crispasr.DecodedAudio>> _inflight = {};

  /// How many concurrent prefetch decodes can be in-flight at once.
  /// Default 1 — the drain loop only ever needs the next file ready.
  /// Set to 2 if a "running + queued + queued+1" lookahead emerges.
  final int _maxInflight = 2;

  /// Fire-and-forget prefetch. Subsequent calls for the same path
  /// short-circuit to the same Future so a double-fire doesn't
  /// double the work. Returns the Future the caller can optionally
  /// await; the drain loop typically discards it because
  /// [consume] is what actually delivers the samples.
  Future<crispasr.DecodedAudio>? prefetch(String absolutePath) {
    if (_inflight.containsKey(absolutePath)) {
      return _inflight[absolutePath];
    }
    if (_inflight.length >= _maxInflight) {
      // Cap reached — skip silently. The drain loop will pay the
      // decode cost synchronously on the slow path. Logging at
      // debug because this is expected backpressure, not an error.
      Log.instance.d('prefetch',
          'cap reached, skipping prefetch for $absolutePath',
          fields: {'inflight': _inflight.length, 'cap': _maxInflight});
      return null;
    }
    final fut = Isolate.run<crispasr.DecodedAudio>(() {
      // Re-open libcrispasr in the worker isolate. The lazy-open
      // path in crispasr.decodeAudioFile is idempotent so we don't
      // have to manage the handle ourselves.
      return crispasr.decodeAudioFile(absolutePath);
    });
    _inflight[absolutePath] = fut;
    Log.instance
        .d('prefetch', 'kicked off', fields: {'file': absolutePath});
    // Best-effort cleanup if the decode throws — we don't want a
    // sticky error preventing future retries on the same path. The
    // `Future.then` form keeps the error flow simple: log + drop
    // the cache entry, then re-throw so a consume() caller sees
    // the real error rather than a silent null.
    fut.then<crispasr.DecodedAudio>(
      (value) => value,
      onError: (Object e, StackTrace st) {
        Log.instance.d(
            'prefetch', 'decode failed (will retry on consume): $e',
            fields: {'file': absolutePath});
        _inflight.remove(absolutePath);
        throw e;
      },
    );
    return fut;
  }

  /// Hand off the decoded audio for [absolutePath] to the caller and
  /// drop the cache entry. Returns null when nothing was prefetched
  /// (the caller falls back to a synchronous decode). Awaits the
  /// in-flight Future when the prefetch is still mid-decode — that's
  /// the whole point of pipeline parallelism.
  Future<crispasr.DecodedAudio?> consume(String absolutePath) async {
    final fut = _inflight.remove(absolutePath);
    if (fut == null) return null;
    try {
      return await fut;
    } catch (e, st) {
      Log.instance.d('prefetch',
          'consume found a failed prefetch; caller will fall back: $e',
          fields: {'file': absolutePath}, stack: st);
      return null;
    }
  }

  /// Drop every cached entry — used by `AudioService.dispose` /
  /// `clearAll`. Pending prefetch futures are NOT cancelled (Dart
  /// has no cancel API for Isolate.run) but their results are
  /// unreferenced so the spawned isolate exits when its work
  /// completes.
  void clear() {
    _inflight.clear();
  }

  /// How many prefetches are currently in-flight. Test-only inspection.
  int get inflightCount => _inflight.length;
}

/// Provider — singleton per ProviderScope. The audio service +
/// drain loop both reach for the same instance.
final audioPrefetchServiceProvider =
    Provider<AudioPrefetchService>((ref) => AudioPrefetchService());
