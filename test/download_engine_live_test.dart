// DownloadEngine against the real Hugging Face CDN (PLAN §9.1).
//
// test/model_download_resume_test.dart already pins the resume protocol
// exhaustively — but it does so against a hand-rolled loopback socket
// whose behaviour we choose. That proves the engine handles 206 / 200 /
// 416 / bogus Content-Range correctly; it cannot prove that the *real*
// server the app downloads from behaves the way the fake one does, nor
// that the URLs baked into ModelCatalog still resolve.
//
// This test closes that gap with the cheapest possible real transfer:
// the kokoro `af_heart` voicepack, ~0.5 MB — the smallest entry in the
// catalogue, and the companion the TTS→ASR roundtrip test needs anyway.
// Nothing here is worth a multi-GB fetch; the protocol is covered
// offline and what remains to check is only "does the catalogue URL
// still serve bytes, and are they the same bytes twice".
//
// Determinism is the real assertion. Downloading once and checking
// `size > 0` would pass on a truncated body, an HTML error page, or a
// CDN that hands back a partial. Downloading twice into two fresh
// directories and comparing SHA-1 catches all three: a stable digest
// across independent transfers is the only cheap evidence that the
// engine reassembled the file rather than merely wrote *something*.
//
// Tagged `live` (network), not `slow` (models) — it needs no dylib and
// no GGUF on disk, only RUN_LIVE_TESTS=1. That matches the tag contract
// in dart_test.yaml: `live` is "reaches an external service".
//
// Deliberately NOT calling TestWidgetsFlutterBinding.ensureInitialized()
// — it installs HttpOverrides that stub out the HttpClient dio needs,
// which is the same reason model_download_resume_test.dart avoids it.
//
// Run:
//   RUN_LIVE_TESTS=1 flutter test --tags live test/download_engine_live_test.dart

@Tags(['live'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/services/model_catalog.dart';
import 'package:crisper_weaver/services/model_service.dart';

/// The smallest real file the catalogue points at: a kokoro voicepack.
/// Using the catalogue entry rather than a hard-coded URL is the point —
/// a dead or renamed repo shows up here instead of in a user's download.
const String _voicepackName = 'kokoro-voice-af_heart';

bool get _liveOptIn => Platform.environment['RUN_LIVE_TESTS'] == '1';

String _sha1OfFile(File f) => sha1.convert(f.readAsBytesSync()).toString();

void main() {
  final def = ModelCatalog.crispasrBackendModels[_voicepackName];

  // Catalogue shape check — pure, offline, always runs. If the entry
  // disappears or loses its URL, the live test below would skip for the
  // wrong reason and nobody would notice.
  test('the catalogue still carries a small downloadable voicepack', () {
    expect(def, isNotNull,
        reason: '$_voicepackName vanished from ModelCatalog — pick another '
            'small entry for the live download smoke test');
    final entry = def!;
    expect(entry.url, startsWith('https://'),
        reason: 'voicepack URL must be an absolute https URL: ${entry.url}');
    expect(entry.fileName, endsWith('.gguf'));
    // Guard the "tiny" premise: this test exists precisely because it is
    // cheap. If the estimate ever grows past a few MB, that is a
    // deliberate decision someone should have to make explicitly.
    expect(entry.sizeBytes, lessThan(8 * 1024 * 1024),
        reason: 'the live download smoke test must stay small; '
            '${entry.fileName} is estimated at ${entry.sizeBytes} bytes');
  });

  group('DownloadEngine vs Hugging Face', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('cw_download_live_');
    });

    tearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {
        // A leaked temp dir is not worth failing a live run over.
      }
    });

    test('fetches a real file and gets the same bytes twice', () async {
      if (!_liveOptIn) {
        markTestSkipped('Set RUN_LIVE_TESTS=1 to run live network tests');
        return;
      }
      final entry = def;
      if (entry == null) {
        markTestSkipped('$_voicepackName is not in the catalogue');
        return;
      }

      // Two independent transfers into two fresh files. Fresh, because a
      // second download onto the first one would exercise resume (which
      // the offline suite already covers) rather than "is the CDN
      // handing us a consistent object".
      final digests = <String>[];
      final sizes = <int>[];
      for (var attempt = 1; attempt <= 2; attempt++) {
        final dest = File('${tmp.path}/attempt$attempt-${entry.fileName}');
        final engine = DownloadEngine(Dio());

        var sawProgress = false;
        await engine.download(
          entry.url,
          dest.path,
          expectedSize: entry.sizeBytes,
          onProgress: (_) => sawProgress = true,
        );

        expect(dest.existsSync(), isTrue,
            reason: 'attempt $attempt produced no file at ${dest.path}');
        final size = dest.lengthSync();
        expect(size, greaterThan(0),
            reason: 'attempt $attempt wrote an empty file');
        // A GGUF starts with the four magic bytes "GGUF". An HTML error
        // page or an HTTP body we mis-assembled would not, and it is the
        // one check that distinguishes "bytes arrived" from "the *right*
        // bytes arrived" without knowing the digest up front.
        final head = dest.readAsBytesSync().take(4).toList();
        expect(String.fromCharCodes(head), 'GGUF',
            reason: 'attempt $attempt did not download a GGUF — got '
                '$head; the URL may now serve an error page');

        sizes.add(size);
        digests.add(_sha1OfFile(dest));
        // Progress reporting is what the Model Manager's UI binds to; a
        // silent download is a UI regression even when the file is fine.
        // It only fires every 250 ms, so a very fast small transfer can
        // legitimately report nothing — hence a printOnFailure note
        // rather than an assertion.
        printOnFailure('attempt $attempt: $size bytes, '
            'progress_callbacks=${sawProgress ? "yes" : "none (fast path)"}');
      }

      expect(sizes[0], sizes[1],
          reason: 'the two downloads differ in length (${sizes[0]} vs '
              '${sizes[1]}) — the transfer is not deterministic');
      expect(digests[0], digests[1],
          reason: 'SHA-1 differs between two downloads of the same URL '
              '(${digests[0]} vs ${digests[1]}) — bytes were dropped, '
              'duplicated or mis-spliced');
      printOnFailure('stable sha1=${digests[0]} over ${sizes[0]} bytes');
    });

    test('a 404 URL fails loudly instead of leaving a plausible file',
        () async {
      if (!_liveOptIn) {
        markTestSkipped('Set RUN_LIVE_TESTS=1 to run live network tests');
        return;
      }
      // Same host, same auth shape, a path that cannot exist. The engine
      // must surface the failure rather than write a zero-byte (or
      // error-page) file that the caller would then checksum.
      final dest = File('${tmp.path}/missing.gguf');
      final engine = DownloadEngine(Dio());
      await expectLater(
        engine.download(
          'https://huggingface.co/cstr/kokoro-voices-GGUF/resolve/main/'
          'definitely-not-a-real-voicepack-9f3c1.gguf',
          dest.path,
          expectedSize: 1024,
        ),
        throwsA(isA<Exception>()),
      );
      // Whatever it threw, it must not have left something that looks
      // like a finished model.
      if (dest.existsSync()) {
        final head = dest.lengthSync() >= 4
            ? String.fromCharCodes(dest.readAsBytesSync().take(4).toList())
            : '';
        expect(head, isNot('GGUF'),
            reason: 'a failed download left a GGUF-looking file behind');
      }
    });
  });
}
