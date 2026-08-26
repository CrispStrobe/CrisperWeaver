// Web stub for llm_abort_flag.dart — the real one shares an `Int32` on the
// native heap between isolates, and `dart:ffi` does not exist on web.
//
// Nothing here is reachable in practice: the local chat LLM runs through
// libcrispasr, which web has no way to load (web routes through
// HfSpaceEngine). The stub exists so the import graph resolves, and it
// keeps the same in-memory semantics so any caller that does reach it
// behaves sanely rather than throwing.
//
// Reminder from PLAN §gate-blind-spots: `flutter analyze` and `flutter test`
// never compile this file. A signature that drifts from the real class shows
// up only as a red `flutter build web`.
class LlmAbortFlag {
  LlmAbortFlag();

  LlmAbortFlag.fromAddress(int address);

  /// No native cell to point at. Callers pass this across an isolate
  /// boundary that web never crosses.
  int get address => 0;

  bool _cancelled = false;
  bool _disposed = false;

  bool get cancelled => !_disposed && _cancelled;

  void cancel() {
    if (!_disposed) _cancelled = true;
  }

  void reset() {
    if (!_disposed) _cancelled = false;
  }

  void dispose() => _disposed = true;
}
