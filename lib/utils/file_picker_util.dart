// Wrapper around `file_picker` that survives Android `Unknown_path`.
//
// file_picker can throw PlatformException(Unknown_path) when the user picks
// a content:// URI it can't resolve to a real file path — typically a
// cloud-backed Drive / OneDrive / Files entry that hasn't been materialized
// locally. The fix is to use PlatformFile.readAsByteStream(), then stage the
// byte stream to a temp file under getTemporaryDirectory() that we own and
// can hand to FFI decoders as a normal filesystem path.
//
// Every screen that called `FilePicker.pickFiles` was vulnerable to the same
// failure; the wrapper lives here so they all share one fallback strategy +
// one source of truth for the user-facing error message.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
export 'package:file_picker/file_picker.dart' show FileType;
import 'package:flutter/services.dart' show PlatformException;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/log_service.dart';
import 'platform_utils.dart' as plat;

/// Result of [pickFilesRobust]. `localPaths` are guaranteed to be
/// filesystem paths the caller can hand to a regular `File` open —
/// either the picker returned them directly, or they were staged to a
/// temp file via the readAsByteStream fallback.
class RobustFilePick {
  final List<String> localPaths;

  /// Raw file bytes — populated on web where filesystem paths are
  /// unavailable. On native platforms this is null; use [localPaths].
  final List<Uint8List>? fileBytes;

  /// Original file names — populated alongside [fileBytes] on web.
  final List<String>? fileNames;

  /// True iff at least one file went through the readAsByteStream + temp-
  /// staging fallback (caller can use this to log / show the user a
  /// "copied from cloud" note if relevant).
  final bool usedCloudFallback;

  const RobustFilePick({
    required this.localPaths,
    required this.usedCloudFallback,
    this.fileBytes,
    this.fileNames,
  });

  static const RobustFilePick empty =
      RobustFilePick(localPaths: <String>[], usedCloudFallback: false);

  bool get isEmpty => localPaths.isEmpty && (fileBytes?.isEmpty ?? true);
  bool get isNotEmpty => !isEmpty;

  /// True when the pick result contains raw bytes (web path).
  bool get hasBytesOnly =>
      localPaths.isEmpty && fileBytes != null && fileBytes!.isNotEmpty;
}

/// Thrown when the picker raised `Unknown_path` and the readAsByteStream
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
/// [type] – the broad category shown to the OS picker.  Use
/// [FileType.audio] when picking audio files so that Android shows
/// **all** audio files as selectable (instead of greying out
/// extensions whose MIME type Android can't resolve).  When a broad
/// [type] is given together with [allowedExtensions], the picker
/// uses [type] for the OS filter, and results are **post-filtered**
/// to the requested extensions.
///
/// If [type] is `null`, the behaviour is the legacy default:
/// `FileType.custom` when [allowedExtensions] is non-empty,
/// `FileType.any` otherwise.
///
/// Throws [FilePickerCloudUriUnsupported] if both the normal and
/// the readAsByteStream-fallback picks fail. Returns
/// [RobustFilePick.empty] if the user cancelled.
Future<RobustFilePick> pickFilesRobust({
  List<String>? allowedExtensions,
  bool allowMultiple = false,
  String? dialogTitle,
  FileType? type,
}) async {
  final hasExtensions =
      allowedExtensions != null && allowedExtensions.isNotEmpty;

  // When a broad type (e.g. audio) is given, don't pass extensions to the
  // native picker — we'll post-filter ourselves.
  final bool postFilter = type != null && hasExtensions;

  // Safari silently ignores accept="audio/*" (FileType.audio) — the picker
  // never opens or returns empty. On web, always fall back to FileType.any
  // and rely on the extension post-filter instead.
  final FileType webSafeType =
      (plat.isWeb && type == FileType.audio) ? FileType.any : (type ?? FileType.any);
  final FileType effectiveType = webSafeType == FileType.any && hasExtensions && !plat.isWeb
      ? FileType.custom
      : webSafeType;
  final List<String>? nativeExtensions =
      (postFilter || !hasExtensions || plat.isWeb) ? null : allowedExtensions;

  FilePickerResult? result;
  var usedCloudFallback = false;
  try {
    if (allowMultiple) {
      result = await FilePicker.pickFiles(
        type: effectiveType,
        allowedExtensions: nativeExtensions,
        dialogTitle: dialogTitle,
      );
    } else {
      final file = await FilePicker.pickFile(
        type: effectiveType,
        allowedExtensions: nativeExtensions,
        dialogTitle: dialogTitle,
      );
      if (file != null) {
        result = FilePickerResult([file]);
      }
    }
  } on PlatformException catch (e) {
    final isUnknownPath = (e.code.toLowerCase() == 'unknown_path') ||
        (e.message?.toLowerCase().contains('failed to retrieve path') ?? false);
    if (!isUnknownPath) rethrow;
    Log.instance.i('file-picker',
        'pick threw Unknown_path — retrying with stream fallback');
    try {
      // Re-pick; we'll read via readAsByteStream below when path is null.
      if (allowMultiple) {
        result = await FilePicker.pickFiles(
          type: effectiveType,
          allowedExtensions: nativeExtensions,
          dialogTitle: dialogTitle,
        );
      } else {
        final file = await FilePicker.pickFile(
          type: effectiveType,
          allowedExtensions: nativeExtensions,
          dialogTitle: dialogTitle,
        );
        if (file != null) {
          result = FilePickerResult([file]);
        }
      }
      usedCloudFallback = true;
    } catch (e2, st2) {
      Log.instance.e('file-picker', 'stream fallback pick also failed',
          error: e2, stack: st2);
      throw FilePickerCloudUriUnsupported(e2);
    }
  }

  if (result == null || result.files.isEmpty) {
    return RobustFilePick.empty;
  }

  // When using a broad type (e.g. FileType.audio) with allowedExtensions,
  // the native picker accepted all files of that category.  Drop any files
  // that don't match the requested extensions.
  final extensionSet = postFilter
      ? allowedExtensions.map((e) => e.toLowerCase()).toSet()
      : null;

  // -- Web path: file_picker returns bytes, not filesystem paths ----------
  if (plat.isWeb) {
    final bytes = <Uint8List>[];
    final names = <String>[];
    for (final f in result.files) {
      if (extensionSet != null) {
        final ext = p.extension(f.name).toLowerCase().replaceFirst('.', '');
        if (!extensionSet.contains(ext)) continue;
      }
      bytes.add(await f.readAsBytes());
      names.add(f.name);
    }
    return RobustFilePick(
      localPaths: const [],
      usedCloudFallback: false,
      fileBytes: bytes,
      fileNames: names,
    );
  }

  // -- Native path: resolve to filesystem paths ---------------------------
  final localPaths = <String>[];
  final tmpDir = await getTemporaryDirectory();
  for (final f in result.files) {
    if (extensionSet != null) {
      final ext = p.extension(f.name).toLowerCase().replaceFirst('.', '');
      if (!extensionSet.contains(ext)) continue;
    }
    if (f.path != null) {
      localPaths.add(f.path!);
      continue;
    }
    // Path is null (cloud URI); stage via readAsByteStream.
    try {
      final stream = f.readAsByteStream();
      final safe = f.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final dest = File(p.join(tmpDir.path, 'picker_$safe'));
      final sink = dest.openWrite();
      await stream.forEach(sink.add);
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
