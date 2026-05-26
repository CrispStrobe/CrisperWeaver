// Extract the bundled espeak-ng-data/ asset bundle to a writable
// directory on first launch + tell libespeak-ng where to find it.
//
// Android only — the desktop releases ship the data dir alongside
// the runtime (handled by applyKokoroEspeakDataPath in env_helpers).
// On Android, native libs can't read assets/ directly from the APK
// (it's a zip), so we materialise the files under
// `getApplicationDocumentsDirectory()/espeak-ng-data/` and set
// `CRISPASR_ESPEAK_DATA_PATH` to that path before the first kokoro
// session opens. Without this, kokoro's `espeak_Initialize` fails
// and `kokoro_synthesize` returns no PCM (issue #6 root cause on
// Android).
//
// The asset list is enumerated via AssetManifest.json so we don't
// hardcode the ~600 files in espeak-ng-data/. Extraction is
// idempotent: each file's bytes are written once and skipped on
// subsequent launches.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'env_helpers.dart';
import 'log_service.dart';

class EspeakDataService {
  static const _assetPrefix = 'assets/espeak-ng-data/';
  static const _destSubdir = 'espeak-ng-data';

  /// Extract every `assets/espeak-ng-data/**` entry to the app's docs
  /// dir and set `CRISPASR_ESPEAK_DATA_PATH` so libespeak-ng's
  /// in-process init picks the bundled phoneme tables instead of
  /// failing with "no data found". Returns the extracted path on
  /// success, null when there is nothing to extract (placeholder
  /// asset on desktop builds, or the platform doesn't need this).
  static Future<String?> ensureExtractedAndSetEnv() async {
    // Desktop builds bundle the data dir next to the runtime via the
    // release.yml workflow steps + applyKokoroEspeakDataPath() — they
    // don't need (and don't ship) the asset variant.
    if (!Platform.isAndroid) return null;

    try {
      final manifestJson = await rootBundle.loadString('AssetManifest.json');
      final manifest = json.decode(manifestJson) as Map<String, dynamic>;
      final espeakAssets = manifest.keys
          .where((k) => k.startsWith(_assetPrefix) && !k.endsWith('/.placeholder'))
          .toList(growable: false);

      if (espeakAssets.isEmpty) {
        Log.instance.w('espeak-data',
            'no espeak-ng-data assets in bundle — kokoro will be unusable on this build');
        return null;
      }

      final docs = await getApplicationDocumentsDirectory();
      final destDir = Directory(p.join(docs.path, _destSubdir));
      if (!await destDir.exists()) {
        await destDir.create(recursive: true);
      }

      // Sentinel: drop a marker file once we've finished a full
      // extraction. Subsequent launches skip the whole sweep.
      // Includes asset count so a future bundle bump triggers re-extract.
      final sentinel = File(p.join(destDir.path, '.extracted-v1'));
      final expectedSentinel = '${espeakAssets.length}\n';
      if (await sentinel.exists()) {
        final existing = await sentinel.readAsString();
        if (existing == expectedSentinel) {
          applyKokoroEspeakDataPath(explicitOverride: destDir.path);
          return destDir.path;
        }
      }

      var written = 0;
      for (final assetKey in espeakAssets) {
        final relative = assetKey.substring(_assetPrefix.length);
        final destFile = File(p.join(destDir.path, relative));
        await destFile.parent.create(recursive: true);
        final data = await rootBundle.load(assetKey);
        await destFile.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: false,
        );
        written++;
      }
      await sentinel.writeAsString(expectedSentinel);
      Log.instance.i('espeak-data',
          'extracted espeak-ng-data bundle',
          fields: {'files': written, 'dest': destDir.path});

      applyKokoroEspeakDataPath(explicitOverride: destDir.path);
      return destDir.path;
    } catch (e, st) {
      Log.instance.w('espeak-data', 'failed to extract espeak-ng-data',
          error: e, stack: st);
      return null;
    }
  }
}
