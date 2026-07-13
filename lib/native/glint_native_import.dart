// Conditional export: real FFI codec on native, no-op stub on web.
export 'glint_native.dart'
    if (dart.library.js_interop) 'glint_native_stub.dart';
