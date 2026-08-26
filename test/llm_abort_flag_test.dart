// LlmAbortFlag — the cancel signal that reaches a blocked worker isolate.
//
// The property that matters is that a write from one isolate is visible to a
// read in another, because the whole point is that a SendPort message cannot
// get through: the worker's event loop is stalled inside the synchronous
// native `generate` call for its entire duration. If the shared-word trick
// did not work, cancellation would silently do nothing and only show up as
// "Cancel takes a minute to respond" in the field.

import 'dart:isolate';

import 'package:crisper_weaver/services/llm_abort_flag.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs on another isolate and reports what it saw at the shared address.
Future<bool> _readFlagOnOtherIsolate(int address) =>
    Isolate.run(() => LlmAbortFlag.fromAddress(address).cancelled);

/// Blocks on another isolate until the flag flips, exactly as the
/// `shouldContinue` predicate does inside the native call.
Future<bool> _spinUntilCancelled(int address) => Isolate.run(() {
      final flag = LlmAbortFlag.fromAddress(address);
      // Bounded by wall clock, not iteration count: a fixed loop count
      // finishes in milliseconds on a fast machine and reports "not
      // cancelled" purely because it gave up before the writer ran, which
      // says nothing about whether the flag works.
      final deadline = Stopwatch()..start();
      while (deadline.elapsed < const Duration(seconds: 10)) {
        if (flag.cancelled) return true;
      }
      return false;
    });

void main() {
  test('starts uncancelled', () {
    final flag = LlmAbortFlag();
    addTearDown(flag.dispose);
    expect(flag.cancelled, isFalse);
  });

  test('cancel is visible through a second view of the same address', () {
    final flag = LlmAbortFlag();
    addTearDown(flag.dispose);
    final view = LlmAbortFlag.fromAddress(flag.address);
    expect(view.cancelled, isFalse);
    flag.cancel();
    expect(view.cancelled, isTrue);
  });

  test('reset clears it, so a resumed pass is not poisoned', () {
    final flag = LlmAbortFlag();
    addTearDown(flag.dispose);
    flag.cancel();
    expect(flag.cancelled, isTrue);
    flag.reset();
    expect(flag.cancelled, isFalse);
  });

  test('a write on this isolate is visible on another', () async {
    final flag = LlmAbortFlag();
    addTearDown(flag.dispose);
    expect(await _readFlagOnOtherIsolate(flag.address), isFalse);
    flag.cancel();
    // This is the assertion the entire design rests on: isolates share no
    // Dart heap, but they do share a process, and therefore a native heap.
    expect(await _readFlagOnOtherIsolate(flag.address), isTrue);
  });

  test('a spinning reader on another isolate observes a later cancel',
      () async {
    final flag = LlmAbortFlag();
    addTearDown(flag.dispose);
    // Start the reader BEFORE cancelling — it is already spinning when the
    // write lands, which is the real sequence during a generation.
    final spinning = _spinUntilCancelled(flag.address);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    flag.cancel();
    expect(await spinning, isTrue);
  });

  test('an adopted view never frees the word it does not own', () {
    final owner = LlmAbortFlag();
    final view = LlmAbortFlag.fromAddress(owner.address);
    // If the view freed here, the owner's cancel below would be a
    // use-after-free — and on a debug allocator, a crash.
    view.dispose();
    owner.cancel();
    expect(owner.cancelled, isTrue);
    owner.dispose();
  });

  test('a disposed flag reports uncancelled rather than reading freed memory',
      () {
    final flag = LlmAbortFlag();
    flag.cancel();
    flag.dispose();
    expect(flag.cancelled, isFalse);
    // Idempotent: a double free would abort the process.
    expect(flag.dispose, returnsNormally);
    expect(flag.cancel, returnsNormally);
    expect(flag.reset, returnsNormally);
  });
}
