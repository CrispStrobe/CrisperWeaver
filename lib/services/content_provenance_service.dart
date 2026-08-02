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
/// Embeds provenance metadata so outputs are machine-detectable
/// as artificially generated.
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

  /// Parse the payload of a `c2pa` RIFF chunk into a manifest.
  ///
  /// Split out of [extractFromWav] so a caller that walks the chunk table
  /// itself — `AudioEditService`, which refuses to read a 100 MB recording
  /// into memory just to discover it has no manifest — can decode the
  /// payload without duplicating the padding and error handling.
  static Map<String, dynamic>? decodeManifestPayload(List<int> payload) {
    // Trim the trailing null bytes RIFF pads odd-length chunks with.
    var end = payload.length;
    while (end > 0 && payload[end - 1] == 0) {
      end--;
    }
    if (end == 0) return null;
    try {
      final decoded = jsonDecode(
          utf8.decode(payload.sublist(0, end), allowMalformed: true));
      return decoded is Map<String, dynamic> ? decoded : null;
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
  static Uint8List injectManifestIntoWav(
    Uint8List wavBytes,
    Map<String, dynamic> manifest,
  ) {
    if (wavBytes.length < 44) return wavBytes;
    final chunk = encodeAsRiffChunk(manifest);
    final out = Uint8List(wavBytes.length + chunk.length);
    out.setRange(0, wavBytes.length, wavBytes);
    out.setRange(wavBytes.length, out.length, chunk);
    ByteData.view(out.buffer).setUint32(4, out.length - 8, Endian.little);
    return out;
  }

  /// Derive a manifest for a file produced by editing one that already
  /// carried [source] provenance.
  ///
  /// C2PA models this as an ingredient relationship: the derived asset
  /// keeps the original claim and appends an action describing what was
  /// done to it. So a trimmed clip of AI-generated speech still says "this
  /// came from a TTS model", which is the fact Art. 50(2) cares about, and
  /// additionally says it was trimmed.
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
        return decodeManifestPayload(wavBytes.sublist(offset + 8, end));
      }
      // Advance to next chunk (size padded to even boundary).
      offset += 8 + size + (size.isOdd ? 1 : 0);
    }
    return null;
  }
}
