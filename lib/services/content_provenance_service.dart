import 'dart:convert';
import 'dart:typed_data';

/// Lightweight content provenance for AI-generated audio.
///
/// The `cwpr` RIFF chunk carries a versioned, unsigned application receipt.
/// It records what the application did; it does not authenticate its author,
/// prove the audio's origin, or claim compatibility with C2PA validators.
/// Native COSE/X.509 signing, when available, is a separate TTS code path.
/// Legacy releases put this JSON in a chunk named `c2pa`; those receipts remain
/// readable, but opaque genuine C2PA data is never decoded as our receipt.
class ContentProvenanceService {
  ContentProvenanceService._();

  static const String schema = 'urn:crisperweaver:audio-provenance:1';
  static const String riffChunkId = 'cwpr';
  static const int maxManifestBytes = 1024 * 1024;

  static bool isReceiptChunk(String id) => id == riffChunkId || id == 'c2pa';

  /// Build an unsigned application receipt. Action names retain the legacy
  /// vocabulary for existing CrisperWeaver readers; this is not signed C2PA.
  static Map<String, dynamic> buildManifest({
    required String generator,
    required String generatorVersion,
    String? modelName,
    String? voiceId,
    DateTime? timestamp,
  }) {
    final ts = timestamp ?? DateTime.now();
    return {
      'schema': schema,
      '@type': 'crisperweaver.audio-provenance',
      'signature': 'unsigned',
      'ai_generated': true,
      'claim_generator': '$generator/$generatorVersion',
      'claim_generator_info': [
        {'name': generator, 'version': generatorVersion},
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
        // Abuse-reporting channel. The recipient of a synthetic clip is
        // the person most likely to spot misuse, and they generally have
        // no idea what produced it. Carrying the channel *inside* the
        // manifest means it travels with the file — a policy published
        // only on a website is unreachable to someone holding a WAV.
        {
          '@type': 'crisperweaver.abuse-reporting',
          'acceptable_use_policy': abuseReportingPolicyUrl,
          'report_misuse': abuseReportingUrl,
          'note':
              'This audio was synthesised by CrisperWeaver. If it impersonates '
              'you or someone you know without consent, report it at the URL '
              'above. Voice cloning without the voice owner\'s consent is '
              'prohibited by the acceptable-use policy.',
        },
      ],
    };
  }

  /// Where a recipient of CrisperWeaver-generated audio can report
  /// misuse (EU AI Act Art. 50(4) — supporting the deployer's disclosure
  /// duty by making the content self-describing).
  static const String abuseReportingUrl =
      'https://github.com/CrispStrobe/CrisperWeaver/issues/new?labels=abuse-report&template=abuse-report.md';

  /// The acceptable-use policy the reporting channel enforces.
  static const String abuseReportingPolicyUrl =
      'https://github.com/CrispStrobe/CrisperWeaver/blob/main/ACCEPTABLE_USE.md';

  /// Encode [manifest] as a custom RIFF `cwpr` chunk suitable for appending
  /// to a WAV file. Returns the raw chunk bytes (4-byte ID + 4-byte
  /// size + JSON payload padded to even length).
  static Uint8List encodeAsRiffChunk(Map<String, dynamic> manifest) {
    final json = utf8.encode(jsonEncode(manifest));
    final padded = json.length.isOdd ? json.length + 1 : json.length;
    final chunk = Uint8List(8 + padded);
    chunk.setRange(0, 4, ascii.encode(riffChunkId));
    // Chunk size (little-endian)
    final bd = ByteData.view(chunk.buffer);
    bd.setUint32(4, json.length, Endian.little);
    chunk.setRange(8, 8 + json.length, json);
    return chunk;
  }

  /// Append an unsigned application receipt to [wavBytes]. The chunk is
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
    final manifest = buildManifest(
      generator: generator,
      generatorVersion: generatorVersion,
      modelName: modelName,
      voiceId: voiceId,
      timestamp: timestamp,
    );
    return injectManifestIntoWav(wavBytes, manifest);
  }

  /// Parse our versioned receipt or the legacy unsigned JSON receipt.
  /// Arbitrary JSON and genuine signed C2PA payloads are not our format.
  ///
  /// Split out of [extractFromWav] so a caller that walks the chunk table
  /// itself — `AudioEditService`, which refuses to read a 100 MB recording
  /// into memory just to discover it has no manifest — can decode the
  /// payload without duplicating the padding and error handling.
  static Map<String, dynamic>? decodeManifestPayload(List<int> payload) {
    if (payload.length > maxManifestBytes) return null;
    // Trim the trailing null bytes RIFF pads odd-length chunks with.
    var end = payload.length;
    while (end > 0 && payload[end - 1] == 0) {
      end--;
    }
    if (end == 0) return null;
    try {
      final decoded = jsonDecode(
        utf8.decode(payload.sublist(0, end), allowMalformed: true),
      );
      if (decoded is! Map<String, dynamic>) return null;
      final current =
          decoded['schema'] == schema && decoded['signature'] == 'unsigned';
      final legacy = decoded['@context'] == 'https://c2pa.org/assertions/v1' &&
          decoded['@type'] == 'c2pa.actions' &&
          decoded['claim_generator'] is String &&
          decoded['actions'] is List;
      return current || legacy ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// Inject an already-built [manifest] into [wavBytes], rather than
  /// composing a fresh one as [injectIntoWav] does.
  ///
  /// This is what carrying provenance across an edit needs: the derived
  /// file must keep the *original* claim (which model, which voice, when)
  /// plus a record of the edit — not a new claim asserting CrisperWeaver
  /// generated the trimmed file just now.
  /// A WAV with opaque native C2PA is returned byte-for-byte unchanged: even
  /// changing the RIFF length to append a chunk could invalidate its signature.
  static Uint8List injectManifestIntoWav(
    Uint8List wavBytes,
    Map<String, dynamic> manifest,
  ) {
    if (!_isWav(wavBytes) || !_canAppendReceipt(wavBytes)) return wavBytes;
    final chunk = encodeAsRiffChunk(manifest);
    final out = Uint8List(wavBytes.length + chunk.length);
    out.setRange(0, wavBytes.length, wavBytes);
    out.setRange(wavBytes.length, out.length, chunk);
    ByteData.sublistView(out).setUint32(4, out.length - 8, Endian.little);
    return out;
  }

  /// Derive a manifest for a file produced by editing one that already
  /// carried [source] provenance.
  ///
  /// The derived receipt keeps the original recorded generation action and
  /// adds the edit. This is an unsigned history, not a verified C2PA ingredient
  /// chain. A legacy receipt is upgraded without inventing a creation event.
  ///
  /// Before this existed, `AudioEditService` decoded to PCM and re-encoded
  /// a bare 44-byte WAV, silently dropping the manifest and the LIST/INFO
  /// tags the app had just written — the app stripping its own marking.
  /// The spread-spectrum watermark survived (it lives in the samples), so
  /// the robust mark held; this restores the machine-readable one.
  static Map<String, dynamic> deriveEditedManifest(
    Map<String, dynamic> source, {
    required String editAction,
    required String generator,
    required String generatorVersion,
    DateTime? timestamp,
  }) {
    final ts = timestamp ?? DateTime.now();
    final derived = Map<String, dynamic>.from(source);
    derived.remove('@context');
    derived['schema'] = schema;
    derived['@type'] = 'crisperweaver.audio-provenance';
    derived['signature'] = 'unsigned';
    final actions = <dynamic>[
      ...(source['actions'] is List
          ? source['actions'] as List
          : const <dynamic>[]),
      {
        'action': 'c2pa.edited',
        'softwareAgent': '$generator/$generatorVersion',
        'when': ts.toUtc().toIso8601String(),
        'parameters': {'name': editAction},
      },
    ];
    derived['actions'] = actions;
    return derived;
  }

  /// Whether [wavBytes] carries a provenance manifest naming AI-generated
  /// media — i.e. whether an edit of it has something to preserve.
  static bool hasAiProvenance(Uint8List wavBytes) =>
      extractFromWav(wavBytes) != null;

  /// The `model` / `voice` parameters recorded in [manifest]'s first
  /// `c2pa.created` action, so a derived file can re-emit the same
  /// LIST/INFO tags. Returns `(null, null)` when absent.
  static (String?, String?) modelAndVoiceOf(Map<String, dynamic> manifest) {
    final actions = manifest['actions'];
    if (actions is! List) return (null, null);
    for (final a in actions) {
      if (a is! Map) continue;
      if (a['action'] != 'c2pa.created') continue;
      final params = a['parameters'];
      if (params is! Map) continue;
      final model = params['model'];
      final voice = params['voice'];
      return (model is String ? model : null, voice is String ? voice : null);
    }
    return (null, null);
  }

  /// Extract our latest application receipt, including legacy JSON receipts.
  /// Genuine C2PA chunks are left untouched and require a C2PA verifier.
  static Map<String, dynamic>? extractFromWav(Uint8List wavBytes) {
    if (!_isWav(wavBytes)) return null;

    // Walk RIFF chunks after the 12-byte RIFF header.
    var offset = 12;
    Map<String, dynamic>? receipt;
    while (offset + 8 <= wavBytes.length) {
      final id = String.fromCharCodes(wavBytes.sublist(offset, offset + 4));
      final bd = ByteData.sublistView(wavBytes);
      final size = bd.getUint32(offset + 4, Endian.little);
      final end = offset + 8 + size;
      if (end > wavBytes.length) return null;
      if (isReceiptChunk(id) && size <= maxManifestBytes) {
        receipt =
            decodeManifestPayload(wavBytes.sublist(offset + 8, end)) ?? receipt;
      }
      // Advance to next chunk (size padded to even boundary).
      offset += 8 + size + (size.isOdd ? 1 : 0);
    }
    return receipt;
  }

  static bool _isWav(Uint8List bytes) =>
      bytes.length >= 44 &&
      String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'WAVE';

  static bool _canAppendReceipt(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final size = data.getUint32(offset + 4, Endian.little);
      final end = offset + 8 + size;
      if (end + (size.isOdd ? 1 : 0) > bytes.length) return false;
      if (id == 'c2pa' &&
          (size > maxManifestBytes ||
              decodeManifestPayload(bytes.sublist(offset + 8, end)) == null)) {
        return false;
      }
      offset = end + (size.isOdd ? 1 : 0);
    }
    return offset == bytes.length;
  }
}
