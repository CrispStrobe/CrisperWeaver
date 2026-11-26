import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:crisper_weaver/services/content_provenance_service.dart';
import 'package:crisper_weaver/utils/marked_wav.dart';

Uint8List chunk(String id, List<int> payload) {
  final bytes = Uint8List(8 + payload.length + (payload.length.isOdd ? 1 : 0));
  bytes.setRange(0, 4, ascii.encode(id));
  ByteData.sublistView(bytes).setUint32(4, payload.length, Endian.little);
  bytes.setRange(8, 8 + payload.length, payload);
  return bytes;
}

Uint8List append(Uint8List wav, Uint8List extra) {
  final out = Uint8List.fromList([...wav, ...extra]);
  ByteData.sublistView(out).setUint32(4, out.length - 8, Endian.little);
  return out;
}

void main() {
  final wav = MarkedWav.encode(
    Float32List.fromList([0.1, -0.2, 0.3]),
    16000,
    generatorVersion: 'test',
    timestamp: DateTime.utc(2026),
  );

  test(
    'custom receipt is explicitly unsigned and preserves the audio bytes',
    () {
      final result = ContentProvenanceService.injectIntoWav(
        wav,
        generator: 'CrisperWeaver',
        generatorVersion: 'test',
        modelName: 'piper',
      );
      expect(result.sublist(44, 50), wav.sublist(44, 50));
      final receipt = ContentProvenanceService.extractFromWav(result)!;
      expect(receipt['schema'], ContentProvenanceService.schema);
      expect(receipt['signature'], 'unsigned');
      expect(receipt['ai_generated'], true);
      expect(receipt.containsKey('@context'), false);
      expect(
        String.fromCharCodes(result.sublist(wav.length, wav.length + 4)),
        'cwpr',
      );
    },
  );

  test(
    'RIFF size excludes the alignment byte and views use their own offset',
    () {
      final raw = ContentProvenanceService.encodeAsRiffChunk({'a': 1});
      expect(ByteData.sublistView(raw).getUint32(4, Endian.little), 7);
      expect(raw.length, 16);
      final marked = ContentProvenanceService.injectIntoWav(
        wav,
        generator: 'CrisperWeaver',
        generatorVersion: 'test',
      );
      final prefixed = Uint8List.fromList([1, 2, 3, ...marked, 4]);
      final view = Uint8List.sublistView(prefixed, 3, 3 + marked.length);
      expect(
        ContentProvenanceService.extractFromWav(view)?['signature'],
        'unsigned',
      );
    },
  );

  test(
    'legacy unsigned JSON is readable without impersonating signed C2PA',
    () {
      final legacy = {
        '@context': 'https://c2pa.org/assertions/v1',
        '@type': 'c2pa.actions',
        'claim_generator': 'CrisperWeaver/legacy',
        'actions': [
          {
            'action': 'c2pa.created',
            'when': '2026-01-01',
            'parameters': {'model': 'old'},
          },
        ],
      };
      final oldWav = append(
        wav,
        chunk('c2pa', utf8.encode(jsonEncode(legacy))),
      );
      expect(ContentProvenanceService.extractFromWav(oldWav), legacy);
      final edited = ContentProvenanceService.deriveEditedManifest(
        legacy,
        editAction: 'trim',
        generator: 'CrisperWeaver',
        generatorVersion: 'test',
      );
      expect(edited['schema'], ContentProvenanceService.schema);
      expect(edited['signature'], 'unsigned');
      expect(
        (edited['actions'] as List).first,
        (legacy['actions'] as List).first,
      );
      expect(ContentProvenanceService.modelAndVoiceOf(edited).$1, 'old');
    },
  );

  test('injection leaves opaque native C2PA byte-for-byte unchanged', () {
    final opaque = chunk('c2pa', [0, 0, 0, 20, 106, 117, 109, 98, 255]);
    final native = append(wav, opaque);
    expect(ContentProvenanceService.extractFromWav(native), isNull);
    final marked = ContentProvenanceService.injectIntoWav(
      native,
      generator: 'CrisperWeaver',
      generatorVersion: 'test',
    );
    expect(marked, native);
    // Reading an existing file with both carriers still finds our receipt;
    // this does not validate or modify the native signature.
    final combined = append(
      native,
      ContentProvenanceService.encodeAsRiffChunk(
        ContentProvenanceService.buildManifest(
          generator: 'CrisperWeaver',
          generatorVersion: 'test',
        ),
      ),
    );
    expect(
      ContentProvenanceService.extractFromWav(combined)?['signature'],
      'unsigned',
    );
  });

  test(
    'arbitrary JSON, non-WAV input and truncated chunks do not prove origin',
    () {
      expect(
        ContentProvenanceService.decodeManifestPayload(utf8.encode('{"x":1}')),
        isNull,
      );
      expect(ContentProvenanceService.extractFromWav(Uint8List(100)), isNull);
      final broken = append(wav, chunk('cwpr', [1]));
      ByteData.sublistView(broken)
          .setUint32(wav.length + 4, 9999, Endian.little);
      expect(ContentProvenanceService.extractFromWav(broken), isNull);
    },
  );
}
