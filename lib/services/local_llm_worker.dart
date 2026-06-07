// LocalLlmWorker — §5.1.6 v3 worker isolate for on-device chat
// LLM cleanup / summarisation, backed by CrispASR's chat ABI.
//
// Why a dedicated isolate (not Isolate.run per call): opening a
// CrispasrChatSession is multi-second (loading a 3B GGUF into
// RAM) and the kept session occupies several GB. We want to:
//   - amortise the open cost across every segment of a pass
//   - keep the UI isolate responsive while `generate` blocks
// CrispasrChatSession.generate runs synchronously on the
// calling isolate (upstream's own doc: "Blocks the calling
// isolate for the duration of generation — wrap in Isolate.run
// if the host app needs the UI isolate free."). So the session
// must live in a dedicated worker isolate, with command/reply
// messaging across SendPorts. This file is that worker.
//
// Wire-level protocol — JSON-serialisable maps only, no
// closures, no live FFI handles cross the boundary:
//
//   spawn(args)
//   ↓
//   Worker creates ReceivePort, sends `.sendPort` back on the
//   main's ready port. Then:
//     { 'type': 'ready' }   (libcrispasr probed lazily on 'open')
//     OR { 'type': 'error', 'message': '...' }
//   ↓
//   Per command, main sends:
//     { 'type': 'open',     'replyPort': SendPort,
//       'modelPath': '...', 'openParams': {...} }
//     { 'type': 'generate', 'replyPort': SendPort,
//       'messages': [{role, content}, ...],
//       'generateParams': {...} }
//     { 'type': 'reset',    'replyPort': SendPort }
//     { 'type': 'shutdown' }
//   ↓
//   Worker replies on replyPort:
//     { 'ok': true, 'value'?: ... }
//     OR { 'ok': false, 'error': '...', 'kind'?: 'unsupported'|'open_failed'|'generate_failed'|'closed' }
//
// All ChatException / UnsupportedError paths funnel into the
// `error` reply with a `kind` discriminator so the calling
// service can map back to LocalLlm*Exception types without
// re-throwing.

import 'dart:async';
import 'dart:isolate';

import 'package:crispasr/crispasr.dart' as crispasr;

/// Spawn-time args passed to [localLlmWorkerEntry]. Kept tiny —
/// the worker resolves libcrispasr through the binding's own
/// default-name probe, identical to the rest of this codebase.
class LocalLlmWorkerArgs {
  const LocalLlmWorkerArgs({required this.readySendPort});
  final SendPort readySendPort;
}

/// Top-level isolate entry — must be top-level (not a closure)
/// so `Isolate.spawn` can find it. Lifecycle:
///   1. Create the command ReceivePort, hand its SendPort back.
///   2. Loop on incoming command messages until 'shutdown'.
///   3. Close any open session on the way out.
Future<void> localLlmWorkerEntry(LocalLlmWorkerArgs args) async {
  final cmdReceive = ReceivePort();
  args.readySendPort.send(cmdReceive.sendPort);
  args.readySendPort.send(<String, Object?>{'type': 'ready'});

  crispasr.CrispasrChatSession? session;

  await for (final raw in cmdReceive) {
    if (raw is! Map) continue;
    final type = raw['type'];
    if (type == 'shutdown') {
      try {
        session?.close();
      } catch (_) {/* best effort */}
      cmdReceive.close();
      return;
    }
    final replyPort = raw['replyPort'] as SendPort?;
    if (replyPort == null) continue;

    switch (type) {
      case 'open':
        // Close any prior session — the service only sends 'open'
        // when the config has actually changed.
        try {
          session?.close();
        } catch (_) {}
        session = null;
        final modelPath = raw['modelPath'] as String?;
        if (modelPath == null || modelPath.isEmpty) {
          replyPort.send(<String, Object?>{
            'ok': false,
            'kind': 'open_failed',
            'error': 'modelPath is required',
          });
          break;
        }
        final paramsMap =
            (raw['openParams'] as Map?)?.cast<String, Object?>() ?? const {};
        try {
          session = crispasr.CrispasrChatSession.open(
            modelPath,
            params: _openParamsFromMap(paramsMap),
          );
          replyPort.send(<String, Object?>{
            'ok': true,
            'templateName': session.templateName,
            'nCtx': session.nCtx,
          });
        } on UnsupportedError catch (e) {
          // libcrispasr lacks the chat symbols — the user's
          // build of CrispASR predates the chat ABI. Surface
          // distinctly so the UI can say "upgrade CrispASR".
          replyPort.send(<String, Object?>{
            'ok': false,
            'kind': 'unsupported',
            'error': e.message?.toString() ?? e.toString(),
          });
        } on crispasr.ChatException catch (e) {
          replyPort.send(<String, Object?>{
            'ok': false,
            'kind': 'open_failed',
            'error': e.message,
            'code': e.code,
          });
        } catch (e) {
          replyPort.send(<String, Object?>{
            'ok': false,
            'kind': 'open_failed',
            'error': e.toString(),
          });
        }
        break;

      case 'generate':
      case 'generate_stream':
        final s = session;
        if (s == null) {
          replyPort.send(<String, Object?>{
            'ok': false,
            'kind': 'closed',
            'error': 'no open session — call open first',
          });
          break;
        }
        final messagesRaw = raw['messages'];
        if (messagesRaw is! List) {
          replyPort.send(<String, Object?>{
            'ok': false,
            'kind': 'generate_failed',
            'error': 'messages missing or not a list',
          });
          break;
        }
        final messages = <crispasr.ChatMessage>[];
        for (final m in messagesRaw) {
          if (m is! Map) continue;
          final role = m['role'];
          final content = m['content'];
          if (role is! String || content is! String) continue;
          messages.add(crispasr.ChatMessage(role: role, content: content));
        }
        final genParamsMap =
            (raw['generateParams'] as Map?)?.cast<String, Object?>() ??
                const {};
        final params = _generateParamsFromMap(genParamsMap);
        if (type == 'generate_stream') {
          // Streaming path — send each token delta as it arrives,
          // then a final 'done' message with the full text.
          try {
            final buf = StringBuffer();
            await for (final delta in s.generateStream(
              messages,
              params: params,
            )) {
              buf.write(delta);
              replyPort.send(<String, Object?>{
                'type': 'token',
                'value': delta,
              });
            }
            replyPort.send(<String, Object?>{
              'type': 'done',
              'ok': true,
              'value': buf.toString(),
            });
          } on crispasr.ChatException catch (e) {
            replyPort.send(<String, Object?>{
              'type': 'done',
              'ok': false,
              'kind': 'generate_failed',
              'error': e.message,
              'code': e.code,
            });
          } on StateError catch (e) {
            replyPort.send(<String, Object?>{
              'type': 'done',
              'ok': false,
              'kind': 'closed',
              'error': e.message,
            });
          } catch (e) {
            replyPort.send(<String, Object?>{
              'type': 'done',
              'ok': false,
              'kind': 'generate_failed',
              'error': e.toString(),
            });
          }
        } else {
          // Blocking path — single reply with the full text.
          try {
            final out = await s.generate(
              messages,
              params: params,
            );
            replyPort.send(<String, Object?>{'ok': true, 'value': out});
          } on crispasr.ChatException catch (e) {
            replyPort.send(<String, Object?>{
              'ok': false,
              'kind': 'generate_failed',
              'error': e.message,
              'code': e.code,
            });
          } on StateError catch (e) {
            replyPort.send(<String, Object?>{
              'ok': false,
              'kind': 'closed',
              'error': e.message,
            });
          } catch (e) {
            replyPort.send(<String, Object?>{
              'ok': false,
              'kind': 'generate_failed',
              'error': e.toString(),
            });
          }
        }
        break;

      case 'reset':
        final s = session;
        if (s == null) {
          // Reset on a closed session is a no-op — treat as success
          // so the caller doesn't have to special-case the first call.
          replyPort.send(<String, Object?>{'ok': true});
          break;
        }
        try {
          s.reset();
          replyPort.send(<String, Object?>{'ok': true});
        } on crispasr.ChatException catch (e) {
          replyPort.send(<String, Object?>{
            'ok': false,
            'kind': 'generate_failed',
            'error': e.message,
            'code': e.code,
          });
        } catch (e) {
          replyPort.send(<String, Object?>{
            'ok': false,
            'kind': 'generate_failed',
            'error': e.toString(),
          });
        }
        break;
    }
  }
}

// ---------------------------------------------------------------------------
// Param marshalling helpers — keep aligned with crispasr's `ChatOpenParams`
// / `ChatGenerateParams` field names. Field-by-field rather than reflection
// because the param classes are immutable + accept named optionals only.
// ---------------------------------------------------------------------------

crispasr.ChatOpenParams _openParamsFromMap(Map<String, Object?> m) {
  return crispasr.ChatOpenParams(
    nThreads: _maybeInt(m['nThreads']),
    nThreadsBatch: _maybeInt(m['nThreadsBatch']),
    nCtx: _maybeInt(m['nCtx']),
    nBatch: _maybeInt(m['nBatch']),
    nUbatch: _maybeInt(m['nUbatch']),
    nGpuLayers: _maybeInt(m['nGpuLayers']),
    useMmap: m['useMmap'] as bool? ?? true,
    useMlock: m['useMlock'] as bool? ?? false,
    chatTemplate: m['chatTemplate'] as String?,
  );
}

crispasr.ChatGenerateParams _generateParamsFromMap(Map<String, Object?> m) {
  // The defaults here MUST match crispasr.ChatGenerateParams's own
  // defaults — we don't want to silently shift sampling behaviour
  // when a field is omitted by the caller.
  return crispasr.ChatGenerateParams(
    maxTokens: _maybeInt(m['maxTokens']) ?? 256,
    temperature: _maybeDouble(m['temperature']) ?? 0.8,
    topK: _maybeInt(m['topK']) ?? 40,
    topP: _maybeDouble(m['topP']) ?? 0.95,
    minP: _maybeDouble(m['minP']) ?? 0.05,
    repeatPenalty: _maybeDouble(m['repeatPenalty']) ?? 1.1,
    repeatLastN: _maybeInt(m['repeatLastN']) ?? 64,
    seed: _maybeInt(m['seed']) ?? 0,
    stop: (m['stop'] as List?)?.cast<String>() ?? const [],
  );
}

int? _maybeInt(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return null;
}

double? _maybeDouble(Object? v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is num) return v.toDouble();
  return null;
}
