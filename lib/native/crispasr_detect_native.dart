// Corrected `detectBackendFromGguf`.
//
// The `crispasr` package's own wrapper checks `if (rc != 0) return null`,
// but the C ABI `crispasr_detect_backend_from_gguf` returns
// `strlen(name)` (> 0) on a successful match and 0 on no-match — so the
// package version returns null for EVERY backend it actually detects and
// an empty string only when nothing matched. That inverted check made the
// GGUF-metadata auto-routing (issue #30) and ModelService's post-download
// backend correction silently dead. We call the ABI directly here with
// the correct contract: rc > 0 → the detected backend name; rc <= 0 (no
// match or error) → null.
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'crispasr_import.dart' as crispasr;

/// The concrete CrispASR backend id for the GGUF at [path] (read from its
/// `general.architecture` metadata), or null when the file can't be read
/// or the architecture isn't recognised. [libPath] pins a specific dylib
/// (tests); defaults to the resolved libcrispasr.
String? detectBackendFromGguf(String path, {String? libPath}) {
  final DynamicLibrary lib;
  try {
    lib = DynamicLibrary.open(libPath ?? crispasr.CrispASR.defaultLibName());
  } catch (_) {
    return null;
  }
  if (!lib.providesSymbol('crispasr_detect_backend_from_gguf')) return null;
  final fn = lib.lookupFunction<
      Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Int32),
      int Function(Pointer<Utf8>, Pointer<Utf8>, int)>(
      'crispasr_detect_backend_from_gguf');
  final pathPtr = path.toNativeUtf8();
  const cap = 128;
  final outBuf = calloc<Uint8>(cap);
  try {
    final rc = fn(pathPtr, outBuf.cast<Utf8>(), cap);
    if (rc <= 0) return null; // <= 0: read error / unrecognised architecture
    final name = outBuf.cast<Utf8>().toDartString();
    return name.isEmpty ? null : name;
  } finally {
    calloc.free(pathPtr);
    calloc.free(outBuf);
  }
}
