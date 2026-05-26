// Extract the bundled espeak-ng-data tarball to a writable directory
// on first launch + tell libespeak-ng where to find it.
//
// Android only — the desktop releases ship the data dir alongside
// the runtime (handled by applyKokoroEspeakDataPath in env_helpers).
// On Android, native libs can't read assets/ directly from the APK
// (it's a zip), and Flutter's pubspec `assets:` directive doesn't
// recurse into subdirectories — so we ship the whole espeak-ng-data
// tree as one `assets/espeak-ng-data.tar.gz` blob, materialise it
// under `getApplicationDocumentsDirectory()/espeak-ng-data/` on
// first launch, and set `CRISPASR_ESPEAK_DATA_PATH` to that path
// before the first kokoro session opens. Without this, kokoro's
// `espeak_Initialize` fails and `kokoro_synthesize` returns no PCM
// (issue #6 root cause on Android).
//
// Extraction is idempotent via a sentinel file: subsequent launches
// short-circuit if the tarball's SHA-1 matches what was last
// extracted. A tarball-bytes change (new release with refreshed
// data) busts the sentinel and re-extracts.

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'env_helpers.dart';
import 'log_service.dart';

class EspeakDataService {
  static const _assetKey = 'assets/espeak-ng-data.tar.gz';
  static const _destSubdir = 'espeak-ng-data';

  /// Extract `assets/espeak-ng-data.tar.gz` to the app's docs dir and
  /// set `CRISPASR_ESPEAK_DATA_PATH` so libespeak-ng's in-process
  /// init picks the bundled phoneme tables instead of failing with
  /// "no data found". Returns the extracted path on success, null
  /// when there is nothing to extract (placeholder tarball on
  /// desktop builds) or when the platform doesn't need this
  /// (desktop bundles the data dir directly).
  static Future<String?> ensureExtractedAndSetEnv() async {
    if (!Platform.isAndroid) return null;

    try {
      final tarballBytes = await rootBundle.load(_assetKey);
      final bytes = tarballBytes.buffer
          .asUint8List(tarballBytes.offsetInBytes, tarballBytes.lengthInBytes);
      // Placeholder tarball is < 1 KB. Real data is several MB. Use
      // size as a cheap first check so we don't log "extract failed"
      // on desktop checkouts.
      if (bytes.length < 4096) {
        Log.instance.w('espeak-data',
            'espeak-ng-data tarball is a placeholder — kokoro will be unusable on this build',
            fields: {'bytes': bytes.length});
        return null;
      }

      final docs = await getApplicationDocumentsDirectory();
      final destDir = Directory(p.join(docs.path, _destSubdir));
      if (!await destDir.exists()) {
        await destDir.create(recursive: true);
      }

      final tarballSha = sha1.convert(bytes).toString();
      final sentinel = File(p.join(destDir.path, '.extracted-sha1'));
      if (await sentinel.exists()) {
        final existing = (await sentinel.readAsString()).trim();
        if (existing == tarballSha) {
          applyKokoroEspeakDataPath(explicitOverride: destDir.path);
          return destDir.path;
        }
      }

      // Decode gzip → tar → write each entry. archive's TarDecoder
      // gives us TarFile entries (file / directory) with full
      // relative paths preserved, so the lang/<family>/ and
      // voices/!v/ subdir layout makes it through intact.
      final decoded = const GZipDecoder().decodeBytes(bytes);
      final tar = TarDecoder().decodeBytes(decoded);

      var written = 0;
      for (final entry in tar.files) {
        if (!entry.isFile) continue;
        final rel = entry.name.startsWith('./')
            ? entry.name.substring(2)
            : entry.name;
        if (rel.isEmpty || rel == '.placeholder') continue;
        final destFile = File(p.join(destDir.path, rel));
        await destFile.parent.create(recursive: true);
        await destFile.writeAsBytes(entry.content as List<int>, flush: false);
        written++;
      }
      await sentinel.writeAsString('$tarballSha\n');
      Log.instance.i('espeak-data', 'extracted espeak-ng-data tarball',
          fields: {
            'files': written,
            'dest': destDir.path,
            'sha1': tarballSha.substring(0, 12),
          });

      applyKokoroEspeakDataPath(explicitOverride: destDir.path);
      return destDir.path;
    } catch (e, st) {
      Log.instance.w('espeak-data', 'failed to extract espeak-ng-data',
          error: e, stack: st);
      return null;
    }
  }
}
