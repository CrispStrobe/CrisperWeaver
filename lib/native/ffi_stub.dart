// Web stub for dart:ffi — provides no-op types for files that directly
// import dart:ffi (diarization_service.dart, speaker_id_service.dart).
//
// Only the types actually referenced in those files are stubbed.

// ---------------------------------------------------------------------------
// DynamicLibrary
// ---------------------------------------------------------------------------

class DynamicLibrary {
  DynamicLibrary._();

  static DynamicLibrary open(String name) {
    throw UnsupportedError('DynamicLibrary.open is not available on web');
  }

  static DynamicLibrary process() {
    throw UnsupportedError('DynamicLibrary.process is not available on web');
  }

  F lookupFunction<T extends Function, F extends Function>(String symbolName) {
    throw UnsupportedError('lookupFunction is not available on web');
  }

  bool providesSymbol(String symbolName) => false;
}
