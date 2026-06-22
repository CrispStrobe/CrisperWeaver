import 'dart:convert';
import 'dart:typed_data';

/// Lightweight content provenance for AI-generated audio.
///
/// Implements a JSON-LD provenance manifest embedded as a custom RIFF
/// chunk (`c2pa`) in WAV files. The manifest follows the C2PA assertion
/// vocabulary (https://c2pa.org/specifications/) so C2PA-aware tools
/// can discover and parse it, while remaining a valid RIFF chunk that
/// non-aware parsers skip.
///
/// This is NOT a full C2PA implementation (which requires CBOR + COSE
/// signing + X.509 certificates). It is the subset that can be
/// implemented without external dependencies: an unsigned provenance
/// claim that records the generator, model, and creation context.
/// Full C2PA signing can be layered on top when a Dart COSE library
/// ships.
///
/// EU AI Act Article 50(2): "Providers of AI systems ... shall ensure
/// that the outputs of the AI system are marked in a machine-readable
/// format and detectable as artificially generated or manipulated."
class ContentProvenanceService {
  ContentProvenanceService._();

  /// Build a C2PA-vocabulary provenance manifest as JSON-LD.
  static Map<String, dynamic> buildManifest({
    required String generator,
    required String generatorVersion,
    String? modelName,
    String? voiceId,
    DateTime? timestamp,
  }) {
    final ts = timestamp ?? DateTime.now();
    return {
      '@context': 'https://c2pa.org/assertions/v1',
      '@type': 'c2pa.actions',
      'claim_generator': '$generator/$generatorVersion',
      'claim_generator_info': [
        {
          'name': generator,
          'version': generatorVersion,
        }
      ],
      'actions': [
        {
          'action': 'c2pa.created',
          'digitalSourceType':
              'http://cv.iptc.org/newscodes/digitalsourcetype/trainedAlgorithmicMedia',
          'softwareAgent': '$generator/$generatorVersion',
          'when': ts.toUtc().toIso8601String(),
          if (modelName != null) 'parameters': {
            'model': modelName,
            if (voiceId != null) 'voice': voiceId,
          },
        }
      ],
      'assertions': [
        {
          '@type': 'c2pa.training-mining',
          'entries': [
            {
              'use': 'notAllowed',
              'constraint_info':
                  'This AI-generated audio may not be used to train AI models without explicit permission.',
            }
          ],
        },
      ],
    };
  }

  /// Encode [manifest] as a RIFF `c2pa` chunk suitable for appending
  /// to a WAV file. Returns the raw chunk bytes (4-byte ID + 4-byte
  /// size + JSON payload padded to even length).
  static Uint8List encodeAsRiffChunk(Map<String, dynamic> manifest) {
    final json = utf8.encode(jsonEncode(manifest));
    final padded = json.length.isOdd ? json.length + 1 : json.length;
    final chunk = Uint8List(8 + padded);
    // Chunk ID: 'c2pa'
    chunk[0] = 0x63; // 'c'
    chunk[1] = 0x32; // '2'
    chunk[2] = 0x70; // 'p'
    chunk[3] = 0x61; // 'a'
    // Chunk size (little-endian)
    final bd = ByteData.view(chunk.buffer);
    bd.setUint32(4, padded, Endian.little);
    chunk.setRange(8, 8 + json.length, json);
    return chunk;
  }

  /// Inject a C2PA provenance chunk into [wavBytes]. The chunk is
  /// appended after the existing chunks (before EOF) and the RIFF
  /// header's file size is updated. Returns the augmented WAV.
  ///
  /// If [wavBytes] is too short to be a valid WAV, returns unchanged.
  static Uint8List injectIntoWav(
    Uint8List wavBytes, {
    required String generator,
    required String generatorVersion,
    String? modelName,
    String? voiceId,
    DateTime? timestamp,
  }) {
    if (wavBytes.length < 44) return wavBytes;

    final manifest = buildManifest(
      generator: generator,
      generatorVersion: generatorVersion,
      modelName: modelName,
      voiceId: voiceId,
      timestamp: timestamp,
    );
    final chunk = encodeAsRiffChunk(manifest);

    // Append the c2pa chunk to the WAV and update the RIFF size.
    final out = Uint8List(wavBytes.length + chunk.length);
    out.setRange(0, wavBytes.length, wavBytes);
    out.setRange(wavBytes.length, out.length, chunk);

    // Update RIFF header size (offset 4, little-endian uint32).
    final bd = ByteData.view(out.buffer);
    bd.setUint32(4, out.length - 8, Endian.little);

    return out;
  }

  /// Extract and parse a C2PA manifest from [wavBytes] if present.
  /// Returns null if no `c2pa` chunk is found.
  static Map<String, dynamic>? extractFromWav(Uint8List wavBytes) {
    if (wavBytes.length < 44) return null;

    // Walk RIFF chunks after the 12-byte RIFF header.
    var offset = 12;
    while (offset + 8 <= wavBytes.length) {
      final id = String.fromCharCodes(wavBytes.sublist(offset, offset + 4));
      final bd = ByteData.view(wavBytes.buffer);
      final size = bd.getUint32(offset + 4, Endian.little);
      if (id == 'c2pa') {
        final end = offset + 8 + size;
        if (end > wavBytes.length) return null;
        final json = utf8.decode(
            wavBytes.sublist(offset + 8, end),
            allowMalformed: true);
        try {
          return jsonDecode(json) as Map<String, dynamic>;
        } catch (_) {
          return null;
        }
      }
      // Advance to next chunk (size padded to even boundary).
      offset += 8 + size + (size.isOdd ? 1 : 0);
    }
    return null;
  }
}
