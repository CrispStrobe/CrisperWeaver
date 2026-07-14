// Conditional export: real FFI backend-detection on native, null on web.
export 'crispasr_detect_native.dart'
    if (dart.library.js_interop) 'crispasr_detect_stub.dart';
