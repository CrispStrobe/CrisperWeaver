// LlmAbortFlag — a cancel signal that reaches a blocked worker isolate.
//
// `CrispasrChatSession.generate` takes a `shouldContinue` predicate that the
// C side calls synchronously, from inside the running compute graph, once per
// prompt batch and once per sampled token. That predicate executes on the
// worker isolate — the same isolate that is blocked for the whole of
// generation.
//
// So a cancel message cannot travel by SendPort. Dart delivers port messages
// on the event loop, and the event loop is exactly what a synchronous native
// call is not servicing. By the time the worker could read the message, the
// generation it was meant to stop has already finished.
//
// Dart isolates share no mutable heap, but they do share a process, and so
// they share the native heap. One `Int32` allocated with `calloc` is visible
// at the same address from both sides. The main isolate writes 1; the
// predicate on the worker reads it. That is the whole mechanism.
//
// Word-sized aligned loads and stores do not tear, and the protocol is
// one-way and monotonic — 0 becomes 1 and never goes back — so the worst
// case of a racing read is observing the cancel one token later than it was
// requested. There is nothing here to make atomic.
//
// Before this, `CleanupCancelToken` was only checked BETWEEN segments
// (`local_llm_cleanup_service.dart`), so pressing Cancel during a long
// segment still waited out that whole generation.

import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Owns the shared word. Create on the main isolate, pass [address] to the
/// worker, and [dispose] when the pass is over.
class LlmAbortFlag {
  LlmAbortFlag() : _cell = calloc<Int32>() {
    _cell.value = 0;
  }

  /// Adopt a flag allocated by another isolate. The adopting side never
  /// frees: ownership stays with whoever called the default constructor.
  LlmAbortFlag.fromAddress(int address)
      : _cell = Pointer<Int32>.fromAddress(address),
        _owned = false;

  final Pointer<Int32> _cell;
  bool _owned = true;
  bool _disposed = false;

  /// Pass this across the isolate boundary — it is a plain int, so it
  /// survives the SendPort's JSON-ish constraints with nothing to serialise.
  int get address => _cell.address;

  /// Read by the `shouldContinue` predicate. Cheap by construction: one
  /// load, no allocation, no call back into the session (which would
  /// deadlock on the session mutex the generation holds).
  bool get cancelled => !_disposed && _cell.value != 0;

  /// Request cancellation. Safe to call repeatedly and from either isolate.
  void cancel() {
    if (_disposed) return;
    _cell.value = 1;
  }

  /// Reset between segments of a batch, so one cancelled segment does not
  /// poison the rest of a pass that the user then resumed.
  void reset() {
    if (_disposed) return;
    _cell.value = 0;
  }

  /// Free the word. Only the allocating isolate does this, and only once
  /// every worker that holds the address has stopped reading it — a freed
  /// address read by a still-running predicate is a use-after-free.
  void dispose() {
    if (_disposed || !_owned) {
      _disposed = true;
      return;
    }
    _disposed = true;
    calloc.free(_cell);
  }
}
