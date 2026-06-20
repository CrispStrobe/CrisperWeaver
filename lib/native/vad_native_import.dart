// Conditional export: real FFI VAD on native, no-op on web.
export 'vad_native.dart' if (dart.library.js_interop) 'vad_native_stub.dart';
