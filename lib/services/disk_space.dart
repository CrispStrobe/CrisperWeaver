// Real free-space probe for the download-precheck in ModelService.
//
// `dart:io` doesn't expose filesystem statistics natively, so this
// reaches into libc / kernel32 directly via FFI. On POSIX
// (Linux / macOS / Android / iOS) it's `statvfs(path, &buf)` →
// `f_bavail × f_frsize` (free bytes for non-root callers). On Windows
// it's `GetDiskFreeSpaceExW(path, &avail, &total, &free)` from
// kernel32.dll — the `avail` value already accounts for quotas the
// user actually has. Returns -1 if neither call succeeds; the caller
// uses that as "skip the precheck and let the OS surface a real
// out-of-space error during the write".
//
// Issue #8 root cause: ModelService previously hardcoded
// _getAvailableSpace() to a 5 GB constant, so any model >= ~4.2 GB
// (MiMo ASR q4_k, granite-speech-4.1-2b q4_k, …) triggered a false
// "Insufficient storage" before the download even started.

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'log_service.dart';

/// Available filesystem space (in bytes) the user can write into at
/// [path]. Returns -1 when probing isn't supported on this platform
/// (the caller should treat that as "skip the precheck").
int getAvailableDiskSpace(String path) {
  try {
    if (Platform.isWindows) return _windowsFreeSpace(path);
    if (Platform.isMacOS ||
        Platform.isLinux ||
        Platform.isAndroid ||
        Platform.isIOS) {
      return _posixStatvfs(path);
    }
  } catch (e, st) {
    Log.instance.w('disk-space', 'free-space probe threw',
        error: e, stack: st, fields: {'path': path});
  }
  return -1;
}

// ===== POSIX statvfs =====
//
// struct statvfs (Linux/Android — fields differ slightly on macOS/iOS
// but the layout we touch (f_bsize, f_frsize, f_bavail) sits at
// matching offsets in all four flavours of the struct as long as we
// statically pin to native long sizes. Use 64-bit fields everywhere
// (statvfs64 on Linux/Android) so we don't truncate >4 GB free counts.

// Field names mirror the POSIX `struct statvfs` layout — keeping the
// underscored C names makes the FFI mapping legible at a glance.
// ignore_for_file: non_constant_identifier_names, unused_field
final class _StatVfs64 extends Struct {
  @Uint64()
  external int f_bsize;
  @Uint64()
  external int f_frsize;
  @Uint64()
  external int f_blocks;
  @Uint64()
  external int f_bfree;
  @Uint64()
  external int f_bavail;
  @Uint64()
  external int f_files;
  @Uint64()
  external int f_ffree;
  @Uint64()
  external int f_favail;
  @Uint64()
  external int f_fsid;
  @Uint64()
  external int f_flag;
  @Uint64()
  external int f_namemax;
  // Padding / spare. Real struct is ~88 bytes; pin to 128 to cover
  // every flavour without overrunning.
  @Uint64()
  external int _spare0;
  @Uint64()
  external int _spare1;
  @Uint64()
  external int _spare2;
  @Uint64()
  external int _spare3;
}

int _posixStatvfs(String path) {
  // `statvfs64` exists on Linux/Android with 32-bit ABI fallback; on
  // macOS/iOS only `statvfs` exists but is already 64-bit-clean. Probe
  // both names and use whichever resolves.
  final libc = DynamicLibrary.process();
  late final int Function(Pointer<Utf8>, Pointer<_StatVfs64>) statvfs;
  try {
    statvfs = libc.lookupFunction<
        Int32 Function(Pointer<Utf8>, Pointer<_StatVfs64>),
        int Function(Pointer<Utf8>, Pointer<_StatVfs64>)>('statvfs64');
  } catch (_) {
    statvfs = libc.lookupFunction<
        Int32 Function(Pointer<Utf8>, Pointer<_StatVfs64>),
        int Function(Pointer<Utf8>, Pointer<_StatVfs64>)>('statvfs');
  }
  final pathPtr = path.toNativeUtf8();
  final bufPtr = calloc<_StatVfs64>();
  try {
    final rc = statvfs(pathPtr, bufPtr);
    if (rc != 0) return -1;
    final buf = bufPtr.ref;
    // Prefer f_frsize (fragment size) — that's what f_bavail counts in.
    final blkSize = buf.f_frsize != 0 ? buf.f_frsize : buf.f_bsize;
    return buf.f_bavail * blkSize;
  } finally {
    calloc.free(pathPtr);
    calloc.free(bufPtr);
  }
}

// ===== Windows GetDiskFreeSpaceExW =====

int _windowsFreeSpace(String path) {
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final getFree = kernel32.lookupFunction<
      Int32 Function(Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>,
          Pointer<Uint64>),
      int Function(Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>,
          Pointer<Uint64>)>('GetDiskFreeSpaceExW');
  // The function wants a path that resolves to a drive — feed it the
  // dir directly and let Windows walk up to the mount point.
  final pathPtr = path.toNativeUtf16();
  final avail = calloc<Uint64>();
  final total = calloc<Uint64>();
  final free = calloc<Uint64>();
  try {
    final ok = getFree(pathPtr, avail, total, free);
    if (ok == 0) return -1;
    return avail.value;
  } finally {
    calloc.free(pathPtr);
    calloc.free(avail);
    calloc.free(total);
    calloc.free(free);
  }
}
