// Wrapper around `file_picker` that survives Android `Unknown_path`.
//
// file_picker 11.0.2 throws PlatformException(Unknown_path) when the
// user picks a content:// URI it can't resolve to a real file path —
// typically a cloud-backed Drive / OneDrive / Files entry that hasn't
// been materialized locally. The fix is to retry the pick with
// `withReadStream: true`, then stage the byte stream to a temp file
// under getTemporaryDirectory() that we own and can hand to FFI
// decoders as a normal filesystem path.
//
// Every screen that called `FilePicker.pickFiles` was vulnerable to
// the same failure; the wrapper lives here so they all share one
// fallback strategy + one source of truth for the user-facing error
// message.

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/log_service.dart';

/// Result of [pickFilesRobust]. `localPaths` are guaranteed to be
/// filesystem paths the caller can hand to a regular `File` open —
/// either the picker returned them directly, or they were staged to a
/// temp file via the readStream fallback.
class RobustFilePick {
  final List<String> localPaths;

  /// True iff at least one file went through the readStream + temp-
  /// staging fallback (caller can use this to log / show the user a
  /// "copied from cloud" note if relevant).
  final bool usedCloudFallback;

  const RobustFilePick({
    required this.localPaths,
    required this.usedCloudFallback,
  });

  static const RobustFilePick empty =
      RobustFilePick(localPaths: <String>[], usedCloudFallback: false);

  bool get isEmpty => localPaths.isEmpty;
  bool get isNotEmpty => localPaths.isNotEmpty;
}

/// Thrown when the picker raised `Unknown_path` and the readStream
/// fallback also failed. Callers should show a user-facing message
/// asking them to copy the file to local storage first.
class FilePickerCloudUriUnsupported implements Exception {
  final Object underlying;
  FilePickerCloudUriUnsupported(this.underlying);
  @override
  String toString() => 'FilePickerCloudUriUnsupported: $underlying';
}

/// Pick one or more files with the same UX as `FilePicker.pickFiles`,
/// transparently handling Android content:// URIs that can't be
/// resolved to a real path.
///
/// `allowedExtensions` is the same as the upstream API; pass null /
/// empty to mean "any" (and the underlying call uses [FileType.any]).
///
/// Throws [FilePickerCloudUriUnsupported] if both the normal and
/// the readStream-fallback picks fail. Returns
/// [RobustFilePick.empty] if the user cancelled.
Future<RobustFilePick> pickFilesRobust({
  List<String>? allowedExtensions,
  bool allowMultiple = false,
  String? dialogTitle,
}) async {
  final useCustomType =
      allowedExtensions != null && allowedExtensions.isNotEmpty;

  Future<FilePickerResult?> doPick({required bool withReadStream}) {
    return FilePicker.pickFiles(
      type: useCustomType ? FileType.custom : FileType.any,
      allowedExtensions: useCustomType ? allowedExtensions : null,
      allowMultiple: allowMultiple,
      withReadStream: withReadStream,
      dialogTitle: dialogTitle,
    );
  }

  FilePickerResult? result;
  var usedCloudFallback = false;
  try {
    result = await doPick(withReadStream: false);
  } on PlatformException catch (e) {
    final isUnknownPath = (e.code.toLowerCase() == 'unknown_path') ||
        (e.message?.toLowerCase().contains('failed to retrieve path') ?? false);
    if (!isUnknownPath) rethrow;
    Log.instance.i('file-picker',
        'pick threw Unknown_path — retrying with readStream fallback');
    try {
      result = await doPick(withReadStream: true);
      usedCloudFallback = true;
    } catch (e2, st2) {
      Log.instance.e('file-picker', 'readStream fallback pick also failed',
          error: e2, stack: st2);
      throw FilePickerCloudUriUnsupported(e2);
    }
  }

  if (result == null || result.files.isEmpty) {
    return RobustFilePick.empty;
  }

  final localPaths = <String>[];
  final tmpDir = await getTemporaryDirectory();
  for (final f in result.files) {
    if (f.path != null) {
      localPaths.add(f.path!);
      continue;
    }
    if (f.readStream == null) continue;
    try {
      final safe = f.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final dest = File(p.join(tmpDir.path, 'picker_$safe'));
      final sink = dest.openWrite();
      await f.readStream!.forEach(sink.add);
      await sink.flush();
      await sink.close();
      localPaths.add(dest.path);
      usedCloudFallback = true;
      Log.instance.i('file-picker', 'staged cloud file to temp', fields: {
        'name': f.name,
        'temp': dest.path,
        'bytes': await dest.length(),
      });
    } catch (e, st) {
      Log.instance.e('file-picker', 'failed to stage cloud-picked file',
          error: e, stack: st);
    }
  }

  return RobustFilePick(
    localPaths: localPaths,
    usedCloudFallback: usedCloudFallback,
  );
}
