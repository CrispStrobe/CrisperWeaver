// LocalLlmBackend — abstraction over the local chat-LLM transport.
//
// Production uses [IsolateLocalLlmBackend], which spawns the
// long-lived worker isolate defined in `local_llm_worker.dart`
// and marshals commands over a SendPort. Tests inject a stub
// implementation that answers from a closure, so service-level
// behaviour (config gating, batch cancellation, per-segment
// error swallowing, config-change → reopen) can be covered
// without a libcrispasr build or a real chat-capable GGUF on
// the test host.
//
// The interface stays map-shaped — `messages: List<Map<String,
// String>>`, `generateParams: Map<String, Object?>` — because
// these flow through SendPort to the worker isolate as-is.
// The service layer up the stack still speaks in terms of
// LocalLlmConfig and ChatMessage-shaped data; the conversion
// happens at the service boundary, not here.

import 'dart:async';
import 'dart:isolate';

import 'local_llm_cleanup_service.dart' show LocalLlmConfig, LocalLlmException;
import 'local_llm_worker.dart';

abstract class LocalLlmBackend {
  /// True once a session has been opened and not yet disposed.
  /// Useful for callers that want to skip a redundant `open`
  /// when only sampling params changed.
  bool get isOpen;

  /// Open (or reopen) the underlying chat session against the
  /// model in [config]. Closes any prior session first.
  Future<void> open(LocalLlmConfig config);

  /// One-shot generate. Throws [LocalLlmException] on failure
  /// (kind: `unsupported` | `open_failed` | `generate_failed` |
  /// `closed`).
  Future<String> generate({
    required List<Map<String, String>> messages,
    required Map<String, Object?> generateParams,
  });

  /// Streaming generate — yields token deltas as they arrive from
  /// the worker. Throws [LocalLlmException] if the final message
  /// from the worker reports an error. Callers can show
  /// incremental output while the LLM is still generating.
  Stream<String> generateStream({
    required List<Map<String, String>> messages,
    required Map<String, Object?> generateParams,
  });

  /// Clear the KV cache so the next generate re-prefills from
  /// scratch. Idempotent on a closed session (returns success).
  Future<void> reset();

  /// Tear down. Shuts down the underlying worker / closes the
  /// native session. Idempotent.
  Future<void> dispose();
}

/// Production backend — spawns one worker isolate per backend
/// instance, holds it for the lifetime of the service. The
/// worker owns the CrispasrChatSession; we never touch FFI on
/// the calling isolate.
class IsolateLocalLlmBackend implements LocalLlmBackend {
  Isolate? _isolate;
  SendPort? _cmdPort;
  ReceivePort? _readyReceive;
  Completer<void>? _spawnReady;
  bool _open = false;
  bool _disposed = false;

  @override
  bool get isOpen => _open && !_disposed;

  Future<SendPort> _ensureSpawned() async {
    if (_disposed) {
      throw const LocalLlmException(
          'closed', 'backend has been disposed');
    }
    final existing = _cmdPort;
    if (existing != null) return existing;
    if (_spawnReady != null) {
      await _spawnReady!.future;
      return _cmdPort!;
    }
    final ready = ReceivePort();
    _readyReceive = ready;
    _spawnReady = Completer<void>();

    // Spawn the worker. The isolate's first message on `ready`
    // is its command SendPort; the second is `{type: 'ready'}`
    // (or an error map, though the current worker can only
    // error from `open` which runs on demand).
    _isolate = await Isolate.spawn<LocalLlmWorkerArgs>(
      localLlmWorkerEntry,
      LocalLlmWorkerArgs(readySendPort: ready.sendPort),
    );

    final iter = StreamIterator<dynamic>(ready);
    try {
      if (!await iter.moveNext()) {
        throw const LocalLlmException(
            'open_failed', 'worker exited before sending its port');
      }
      final port = iter.current;
      if (port is! SendPort) {
        throw LocalLlmException('open_failed',
            'worker first message was not a SendPort: $port');
      }
      _cmdPort = port;
      if (!await iter.moveNext()) {
        throw const LocalLlmException(
            'open_failed', 'worker exited before signalling ready');
      }
      final first = iter.current;
      if (first is Map && first['type'] == 'ready') {
        _spawnReady!.complete();
        return port;
      }
      final msg = first is Map ? (first['message']?.toString() ?? '$first') : '$first';
      throw LocalLlmException('open_failed', msg);
    } finally {
      // Don't close the ready ReceivePort here — we keep it
      // open through the spawn handshake. It gets closed in
      // dispose() once we're sure no further messages arrive.
      await iter.cancel();
    }
  }

  @override
  Future<void> open(LocalLlmConfig config) async {
    final port = await _ensureSpawned();
    final reply = ReceivePort();
    port.send(<String, Object?>{
      'type': 'open',
      'replyPort': reply.sendPort,
      'modelPath': config.modelPath,
      'openParams': config.toOpenParamsMap(),
    });
    final res = await reply.first;
    reply.close();
    if (res is! Map) {
      throw LocalLlmException('open_failed', 'unexpected reply: $res');
    }
    if (res['ok'] == true) {
      _open = true;
      return;
    }
    final kind = (res['kind'] as String?) ?? 'open_failed';
    final msg = (res['error'] as String?) ?? 'open failed';
    _open = false;
    throw LocalLlmException(kind, msg);
  }

  @override
  Future<String> generate({
    required List<Map<String, String>> messages,
    required Map<String, Object?> generateParams,
  }) async {
    if (!isOpen) {
      throw const LocalLlmException(
          'closed', 'session is not open — call open() first');
    }
    final port = _cmdPort!;
    final reply = ReceivePort();
    port.send(<String, Object?>{
      'type': 'generate',
      'replyPort': reply.sendPort,
      'messages': messages,
      'generateParams': generateParams,
    });
    final res = await reply.first;
    reply.close();
    if (res is! Map) {
      throw LocalLlmException('generate_failed', 'unexpected reply: $res');
    }
    if (res['ok'] == true) {
      final value = res['value'];
      if (value is String) return value;
      throw LocalLlmException('generate_failed',
          'generate reply value was not a string: $value');
    }
    final kind = (res['kind'] as String?) ?? 'generate_failed';
    final msg = (res['error'] as String?) ?? 'generate failed';
    throw LocalLlmException(kind, msg);
  }

  @override
  Stream<String> generateStream({
    required List<Map<String, String>> messages,
    required Map<String, Object?> generateParams,
  }) async* {
    if (!isOpen) {
      throw const LocalLlmException(
          'closed', 'session is not open — call open() first');
    }
    final port = _cmdPort!;
    final reply = ReceivePort();
    port.send(<String, Object?>{
      'type': 'generate_stream',
      'replyPort': reply.sendPort,
      'messages': messages,
      'generateParams': generateParams,
    });
    // The worker sends {type:'token', value:'...'} for each delta,
    // then {type:'done', ok:true/false, ...} as the final message.
    await for (final res in reply) {
      if (res is! Map) continue;
      final msgType = res['type'];
      if (msgType == 'token') {
        final value = res['value'];
        if (value is String) yield value;
      } else if (msgType == 'done') {
        reply.close();
        if (res['ok'] != true) {
          final kind = (res['kind'] as String?) ?? 'generate_failed';
          final msg = (res['error'] as String?) ?? 'generate failed';
          throw LocalLlmException(kind, msg);
        }
        return;
      }
    }
    // If we get here, the port was closed without a 'done' —
    // treat as an error.
    throw const LocalLlmException(
        'closed', 'worker stream ended without a done message');
  }

  @override
  Future<void> reset() async {
    if (!isOpen) return; // reset on a closed session = no-op
    final port = _cmdPort!;
    final reply = ReceivePort();
    port.send(<String, Object?>{
      'type': 'reset',
      'replyPort': reply.sendPort,
    });
    final res = await reply.first;
    reply.close();
    if (res is Map && res['ok'] == true) return;
    final kind = res is Map ? (res['kind'] as String?) ?? 'generate_failed' : 'generate_failed';
    final msg = res is Map ? (res['error'] as String?) ?? 'reset failed' : 'reset failed';
    throw LocalLlmException(kind, msg);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _open = false;
    final port = _cmdPort;
    if (port != null) {
      try {
        port.send(<String, Object?>{'type': 'shutdown'});
      } catch (_) {/* worker already gone */}
    }
    _cmdPort = null;
    _isolate?.kill(priority: Isolate.beforeNextEvent);
    _isolate = null;
    _readyReceive?.close();
    _readyReceive = null;
  }
}
