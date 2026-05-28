// ModelService.probeHfRepoForBackend — drives the HF-API parsing path
// through a canned HttpClientAdapter so the .gguf/.bin filtering, quant
// extraction, repo-namespaced keys, URL construction, and the
// (repoId, backend) persistence side-effect are all covered without
// touching the network.
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisper_weaver/services/model_service.dart';
import 'package:crisper_weaver/services/settings_service.dart';

/// Minimal adapter that answers every request with one canned JSON body.
class _CannedAdapter implements HttpClientAdapter {
  _CannedAdapter(this.body);

  final String body;
  String? lastUrl;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastUrl = options.uri.toString();
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const _hfPayload = '''
{
  "id": "cstr/voxcpm2-GGUF",
  "cardData": {"language": ["en", "zh"]},
  "siblings": [
    {"rfilename": "voxcpm2-q4_k.gguf", "size": 1689498432},
    {"rfilename": "voxcpm2-f16.gguf", "size": 4972550208},
    {"rfilename": "README.md", "size": 1234},
    {"rfilename": "config.json", "size": 99},
    {"rfilename": "ggml-tiny.bin", "size": 77000000}
  ]
}
''';

void main() {
  late SettingsService settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settings = SettingsService(prefs);
  });

  ModelService serviceWith(_CannedAdapter adapter) {
    final dio = Dio()..httpClientAdapter = adapter;
    return ModelService(settings, dio: dio);
  }

  group('probeHfRepoForBackend', () {
    test('returns one ModelDefinition per .gguf/.bin, skips other files',
        () async {
      final svc = serviceWith(_CannedAdapter(_hfPayload));

      final out = await svc.probeHfRepoForBackend(
        repoId: 'cstr/voxcpm2-GGUF',
        backend: 'voxcpm2-tts',
      );

      // README.md + config.json are filtered out; 2 gguf + 1 bin remain.
      expect(out, hasLength(3));
      expect(
        out.map((m) => m.fileName).toSet(),
        {'voxcpm2-q4_k.gguf', 'voxcpm2-f16.gguf', 'ggml-tiny.bin'},
      );
    });

    test('extracts quant, size, backend, namespaced key, and URL', () async {
      final svc = serviceWith(_CannedAdapter(_hfPayload));
      final out = await svc.probeHfRepoForBackend(
        repoId: 'cstr/voxcpm2-GGUF',
        backend: 'voxcpm2-tts',
      );

      final q4 = out.firstWhere((m) => m.fileName == 'voxcpm2-q4_k.gguf');
      expect(q4.quantization, 'q4_k');
      expect(q4.sizeBytes, 1689498432);
      expect(q4.backend, 'voxcpm2-tts');
      expect(q4.name, 'cstr__voxcpm2-GGUF--voxcpm2-q4_k');
      expect(
        q4.url,
        'https://huggingface.co/cstr/voxcpm2-GGUF/resolve/main/voxcpm2-q4_k.gguf',
      );

      final f16 = out.firstWhere((m) => m.fileName == 'voxcpm2-f16.gguf');
      expect(f16.quantization, 'f16');

      // A stem with no recognisable quant token falls back to 'unknown'.
      final bin = out.firstWhere((m) => m.fileName == 'ggml-tiny.bin');
      expect(bin.quantization, 'unknown');
    });

    test('persists the (repoId, backend) pair by default', () async {
      final svc = serviceWith(_CannedAdapter(_hfPayload));
      await svc.probeHfRepoForBackend(
        repoId: 'cstr/voxcpm2-GGUF',
        backend: 'voxcpm2-tts',
        displayPrefix: 'VoxCPM2',
      );

      final repos = settings.hfUserRepos;
      expect(repos, hasLength(1));
      expect(repos.single['repoId'], 'cstr/voxcpm2-GGUF');
      expect(repos.single['backend'], 'voxcpm2-tts');
      expect(repos.single['displayPrefix'], 'VoxCPM2');
    });

    test('persist: false skips the side-effect (replay path)', () async {
      final svc = serviceWith(_CannedAdapter(_hfPayload));
      await svc.probeHfRepoForBackend(
        repoId: 'cstr/voxcpm2-GGUF',
        backend: 'voxcpm2-tts',
        persist: false,
      );
      expect(settings.hfUserRepos, isEmpty);
    });

    test('rejects a repo id without an OWNER/NAME slash', () async {
      final svc = serviceWith(_CannedAdapter(_hfPayload));
      expect(
        () => svc.probeHfRepoForBackend(repoId: 'noslash', backend: 'whisper'),
        throwsArgumentError,
      );
    });

    test('an empty siblings list yields no models and no persistence',
        () async {
      final svc = serviceWith(_CannedAdapter(
          '{"id": "cstr/empty-GGUF", "siblings": []}'));
      final out = await svc.probeHfRepoForBackend(
        repoId: 'cstr/empty-GGUF',
        backend: 'whisper',
      );
      expect(out, isEmpty);
      // Nothing found → nothing persisted.
      expect(settings.hfUserRepos, isEmpty);
    });
  });
}
