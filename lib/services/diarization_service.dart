import '../native/ffi_import.dart';
import 'dart:io';
import 'dart:typed_data';

import '../native/crispasr_import.dart' as crispasr;
import 'package:path/path.dart' as p;

import '../engines/transcription_engine.dart';
import 'audio_service.dart';
import 'log_service.dart';
import 'model_service.dart';
import 'speaker_id_service.dart';

/// Speaker diarization via CrispASR 0.4.5+ shared-lib `diarizeSegments`.
///
/// Four methods are available upstream (energy / xcorr / vad-turns /
/// pyannote). We default to `vadTurns` because it's mono-friendly, needs
/// no extra model file, and returns a stable alternating-speaker
/// labelling on typical conversational audio. The pyannote path (GGUF-
/// based ML diarization, up to 3 speakers) is available when callers
/// ship the pyannote-v3-seg.gguf and pass `method:
/// DiarizeMethod.pyannote`; that wiring is deferred behind a model-
/// manager flow.
///
/// This replaces a ~474 LOC MFCC + k-means stopgap that predated the
/// upstream C-ABI. The shared-lib call runs in one FFI hop and matches
/// exactly what `crispasr --diarize --diarize-method vad-turns`
/// produces on the CLI.
///
/// §5.26.4 — Global diarization timeline (CrispASR #110): linking
/// against CrispASR mid-2026+ automatically gets the global timeline
/// improvement — sherpa/ECAPA runs once on the full audio (not
/// per-slice), giving consistent speaker IDs across chunks.
/// `CrispasrSherpaCache` mirrors the pyannote global-cache pattern.
/// No CrisperWeaver code change needed for this — it's transparent
/// through the existing `diarizeSegments` C API call.
class DiarizationService {
  /// Optional ModelService — used to auto-locate the pyannote-v3-seg
  /// GGUF when the user picks `DiarizeMethod.pyannote` and a model path
  /// isn't supplied explicitly. Null in tests / fixtures.
  final ModelService? modelService;

  /// §5.8.1 — Optional SpeakerIdService for the post-diarisation TitaNet
  /// match pass that resolves cluster labels to enrolled names. Null in
  /// tests / when speaker ID is unavailable.
  final SpeakerIdService? speakerIdService;

  DiarizationService({this.modelService, this.speakerIdService});

  /// Cached pyannote posteriors — computing these is the expensive step
  /// (full encoder pass over the audio). Once computed, re-diarization
  /// (e.g. after the user edits segment boundaries) uses the cache and
  /// skips the encoder. Keyed by audio identity hash (sample count) so
  /// a new audio file invalidates the stale cache.
  crispasr.CrispasrPyannoteCache? _pyannoteCache;
  int? _pyannoteCacheAudioKey;

  /// Dispose cached pyannote posteriors. Call when the audio changes.
  void invalidatePyannoteCache() {
    try {
      _pyannoteCache?.close();
    } catch (e) {
      Log.instance.w('diarize', 'pyannote cache close threw',
          fields: {'err': e.toString()});
    }
    _pyannoteCache = null;
    _pyannoteCacheAudioKey = null;
  }

  /// Locate the pyannote-v3-seg GGUF on disk so the caller doesn't have
  /// to know its exact name. Returns null if no matching file is found.
  Future<String?> _findPyannoteModel() async {
    final svc = modelService;
    if (svc == null) return null;
    try {
      final dir = Directory(svc.whisperCppDir());
      if (!await dir.exists()) return null;
      await for (final ent in dir.list()) {
        if (ent is! File) continue;
        final base = p.basename(ent.path).toLowerCase();
        if (base.startsWith('pyannote') && base.endsWith('.gguf')) {
          return ent.path;
        }
      }
    } catch (e, st) {
      Log.instance.w('diarize', 'failed to locate pyannote GGUF',
          error: e, stack: st);
    }
    return null;
  }

  /// Locate the WeSpeaker embedder GGUF for [crispasr.DiarizeMethod.foxNose].
  /// Same shape as [_findPyannoteModel]: whatever the user downloaded wins,
  /// and a miss is reported rather than guessed at.
  Future<String?> _findFoxnoseEmbedder() async {
    final svc = modelService;
    if (svc == null) return null;
    try {
      final dir = Directory(svc.whisperCppDir());
      if (!await dir.exists()) return null;
      await for (final ent in dir.list()) {
        if (ent is! File) continue;
        final base = p.basename(ent.path).toLowerCase();
        if (base.startsWith('wespeaker') && base.endsWith('.gguf')) {
          return ent.path;
        }
      }
    } catch (e, st) {
      Log.instance.w('diarize', 'failed to locate wespeaker GGUF',
          error: e, stack: st);
    }
    return null;
  }

  /// Fill `seg.speaker` for every segment using the shared-lib diarizer.
  ///
  /// When [audioData] has stereo channel data (non-null `rightChannel`),
  /// the stereo-only diarization methods (energy / xcorr) become
  /// available and the right channel is passed to the C layer.
  /// Otherwise falls back to mono-only methods (vad-turns / pyannote).
  ///
  /// `minSpeakers` / `maxSpeakers` bound the automatic speaker-count
  /// estimate, and `numSpeakers` > 0 pins it and skips estimation.
  ///
  /// These were accepted-but-ignored until CrispASR #324: no method had a
  /// knob for them, so the library decided alone (vad-turns alternates 0/1;
  /// pyannote emits up to 3 per slice). [crispasr.DiarizeMethod.foxNose]
  /// consumes all three, so a caller who knows there are exactly two people
  /// in the room can finally say so. The other methods still ignore them,
  /// and the post-hoc re-clustering below still runs regardless.
  Future<List<TranscriptionSegment>> diarizeSegments(
    AudioData audioData,
    List<TranscriptionSegment> segments, {
    int? minSpeakers,
    int? maxSpeakers,
    int? numSpeakers,
    crispasr.DiarizeMethod method = crispasr.DiarizeMethod.vadTurns,
    String? pyannoteModelPath,
    String? foxnoseEmbedderPath,
    bool enableSpeakerRecognition = false,
    void Function(double progress)? onProgress,
  }) async {
    if (segments.isEmpty) return segments;

    onProgress?.call(0.0);

    final libSegs = segments
        .map((s) => crispasr.DiarizeSegment(t0: s.startTime, t1: s.endTime))
        .toList();

    onProgress?.call(0.2);

    // Resolve a pyannote GGUF path if the user picked the pyannote
    // method but didn't supply a model path explicitly. Falls back to
    // whatever the caller passed in.
    String? resolvedPyannotePath = pyannoteModelPath;
    if (method == crispasr.DiarizeMethod.pyannote &&
        (resolvedPyannotePath == null || resolvedPyannotePath.isEmpty)) {
      resolvedPyannotePath = await _findPyannoteModel();
      if (resolvedPyannotePath == null) {
        Log.instance.w(
            'diarize',
            'pyannote method requested but pyannote-*.gguf not on disk — '
                'falling back to vad-turns');
        method = crispasr.DiarizeMethod.vadTurns;
      }
    }

    // Same treatment for foxNose: resolve the embedder, and degrade to
    // vad-turns rather than handing the C layer a null path (which returns
    // false and leaves every speaker unassigned with no explanation).
    String? resolvedFoxnosePath = foxnoseEmbedderPath;
    if (method == crispasr.DiarizeMethod.foxNose &&
        (resolvedFoxnosePath == null || resolvedFoxnosePath.isEmpty)) {
      resolvedFoxnosePath = await _findFoxnoseEmbedder();
      if (resolvedFoxnosePath == null) {
        Log.instance.w(
            'diarize',
            'foxNose method requested but wespeaker-*.gguf not on disk — '
                'falling back to vad-turns');
        method = crispasr.DiarizeMethod.vadTurns;
      }
    }

    try {
      // When using pyannote, try the pre-computed cache path first.
      // The cache avoids re-running the expensive encoder on the same
      // audio when the user re-diarizes (e.g. after editing segments).
      bool usedCache = false;
      if (method == crispasr.DiarizeMethod.pyannote &&
          resolvedPyannotePath != null) {
        final audioKey = audioData.samples.length;
        final lib = DynamicLibrary.open(crispasr.CrispASR.defaultLibName());
        if (lib.providesSymbol('crispasr_pyannote_cache_compute_abi')) {
          if (_pyannoteCache == null || _pyannoteCacheAudioKey != audioKey) {
            // Compute fresh cache — this is the expensive step.
            invalidatePyannoteCache();
            try {
              _pyannoteCache = crispasr.CrispasrPyannoteCache(
                lib,
                audioData.samples,
                resolvedPyannotePath,
              );
              _pyannoteCacheAudioKey = audioKey;
              Log.instance.i('diarize', 'computed pyannote cache',
                  fields: {'samples': audioKey});
            } catch (e, st) {
              Log.instance.w('diarize', 'pyannote cache compute failed — '
                  'falling back to direct diarize', error: e, stack: st);
            }
          }
          if (_pyannoteCache != null) {
            try {
              _pyannoteCache!.apply(libSegs);
              usedCache = true;
            } catch (e, st) {
              Log.instance.w('diarize', 'pyannote cache apply failed',
                  error: e, stack: st);
            }
          }
        }
      }

      if (!usedCache) {
        final ok = crispasr.diarizeSegments(
          segs: libSegs,
          left: audioData.samples,
          right: audioData.rightChannel,
          isStereo: audioData.isStereo,
          method: method,
          pyannoteModelPath: resolvedPyannotePath,
          foxnoseEmbedderPath: resolvedFoxnosePath,
          // 0 is the library's "use your default" for all three, which is
          // also what null means here — so an unset hint stays unset rather
          // than becoming a hard bound of zero speakers.
          minSpeakers: minSpeakers ?? 0,
          maxSpeakers: maxSpeakers ?? 0,
          numSpeakers: numSpeakers ?? 0,
        );
        if (!ok) {
          Log.instance.w('diarize',
              'crispasr.diarizeSegments returned false — leaving speakers unassigned');
          return segments;
        }
      }
    } catch (e, st) {
      Log.instance.e('diarize', 'diarizeSegments threw', error: e, stack: st);
      return segments;
    }

    onProgress?.call(0.75);

    // Optional re-clustering: when the caller specifies maxSpeakers,
    // extract per-segment embeddings and re-cluster with agglomerative
    // cosine clustering to merge over-segmented speakers down to the
    // requested count. Requires a speaker embedder on disk.
    if (maxSpeakers != null && maxSpeakers > 0 && speakerIdService != null) {
      try {
        final lib = DynamicLibrary.open(crispasr.CrispASR.defaultLibName());
        if (lib.providesSymbol('crispasr_speaker_cluster_abi') &&
            await speakerIdService!.isAvailable) {
          await speakerIdService!.ensureOpenForEmbedding();
          final embedder = speakerIdService!.embedder;
          if (embedder != null) {
            final dim = embedder.dim;
            final allEmbs = Float32List(libSegs.length * dim);
            for (var i = 0; i < libSegs.length; i++) {
              final t0 = libSegs[i].t0;
              final t1 = libSegs[i].t1;
              final s0 = (t0 * 16000).round().clamp(0, audioData.samples.length);
              final s1 = (t1 * 16000).round().clamp(s0, audioData.samples.length);
              if (s1 - s0 < 1600) {
                // <100 ms — too short for a meaningful embedding; fill zeros
                allEmbs.fillRange(i * dim, (i + 1) * dim, 0.0);
                continue;
              }
              final slice = audioData.samples.sublist(s0, s1);
              final emb = embedder.embed(slice);
              if (emb != null && emb.length == dim) {
                allEmbs.setAll(i * dim, emb);
              }
            }
            final labels = crispasr.crispasrAgglomerativeCluster(
              lib,
              allEmbs,
              n: libSegs.length,
              dim: dim,
              maxSpeakers: maxSpeakers,
            );
            // Re-assign speaker labels from clustering output.
            for (var i = 0; i < libSegs.length; i++) {
              libSegs[i] = crispasr.DiarizeSegment(
                t0: libSegs[i].t0,
                t1: libSegs[i].t1,
                speaker: labels[i],
              );
            }
            Log.instance.i('diarize', 're-clustered to $maxSpeakers speakers',
                fields: {'segments': libSegs.length});
          }
        }
      } catch (e, st) {
        Log.instance.w('diarize',
            'agglomerative re-clustering failed — keeping original labels',
            error: e, stack: st);
      }
    }

    onProgress?.call(0.85);

    // §5.8.1 — Optional speaker-recognition pass. Resolve numeric
    // cluster labels to enrolled names via TitaNet when the caller
    // opted in and the prerequisites are met. One match per unique
    // cluster — embeddings are roughly stable per speaker.
    Map<int, String>? clusterToName;
    if (enableSpeakerRecognition && speakerIdService != null) {
      try {
        clusterToName = await _resolveSpeakerNames(audioData, libSegs);
      } catch (e, st) {
        Log.instance.w(
            'diarize', 'speaker recognition pass failed — keeping numeric labels',
            error: e, stack: st);
      }
    }

    onProgress?.call(0.95);

    final out = <TranscriptionSegment>[];
    for (var i = 0; i < segments.length; i++) {
      final spk = libSegs[i].speaker;
      final String? label;
      if (spk < 0) {
        label = segments[i].speaker;
      } else {
        label = clusterToName?[spk] ?? 'Speaker ${spk + 1}';
      }
      out.add(TranscriptionSegment(
        text: segments[i].text,
        startTime: segments[i].startTime,
        endTime: segments[i].endTime,
        speaker: label,
        confidence: segments[i].confidence,
        words: segments[i].words,
        metadata: segments[i].metadata,
      ));
    }

    onProgress?.call(1.0);
    Log.instance.i('diarize', 'diarizeSegments done', fields: {
      'method': method.name,
      'segments': out.length,
      'speakers_seen':
          libSegs.map((s) => s.speaker).where((s) => s >= 0).toSet().length,
      'speakers_resolved': clusterToName?.length ?? 0,
    });
    return out;
  }

  /// §9.6 #110 — Global-scope diarization: takes raw PCM audio and a
  /// window size, creates uniform segments covering the full audio, runs
  /// diarization on all of them at once (so pyannote/sherpa sees the full
  /// timeline), and returns speaker-labelled segments.
  ///
  /// This is useful when you have raw audio but no ASR segments yet, or
  /// want speaker labels independent of the ASR segmentation.
  Future<List<TranscriptionSegment>> diarizeFullAudio(
    AudioData audioData, {
    double windowSeconds = 3.0,
    crispasr.DiarizeMethod method = crispasr.DiarizeMethod.pyannote,
    String? pyannoteModelPath,
    int? maxSpeakers,
    void Function(double progress)? onProgress,
  }) async {
    if (audioData.samples.isEmpty) return const [];

    // Create uniform segments covering the full audio.
    final durationSeconds = audioData.samples.length / 16000.0;
    final segments = <TranscriptionSegment>[];
    var t = 0.0;
    while (t < durationSeconds) {
      final end = (t + windowSeconds).clamp(0.0, durationSeconds);
      segments.add(TranscriptionSegment(
        text: '',
        startTime: t,
        endTime: end,
      ));
      t = end;
      if (end >= durationSeconds) break;
    }

    // Run diarization on the full set of segments.
    return diarizeSegments(
      audioData,
      segments,
      method: method,
      pyannoteModelPath: pyannoteModelPath,
      maxSpeakers: maxSpeakers,
      onProgress: onProgress,
    );
  }

  /// For every unique numeric speaker label, find the longest segment
  /// tagged with it, extract a representative ~3 s PCM slice from its
  /// middle, run the TitaNet matcher once, and build the cluster → name
  /// map. Returns an empty map when speaker ID isn't available
  /// (e.g. TitaNet not downloaded, no enrolled profiles) — callers
  /// just fall back to numeric labels.
  Future<Map<int, String>> _resolveSpeakerNames(
    AudioData audioData,
    List<crispasr.DiarizeSegment> libSegs,
  ) async {
    final svc = speakerIdService;
    if (svc == null) return const {};
    if (!await svc.isAvailable) {
      Log.instance.d('diarize',
          'speaker recognition requested but TitaNet not available — skipping');
      return const {};
    }
    // Longest-segment-per-cluster pick. The longest contiguous chunk
    // gives the most stable embedding (TitaNet was trained on >=3 s
    // utterances).
    final longestPerCluster = <int, int>{}; // speaker → segment index
    for (var i = 0; i < libSegs.length; i++) {
      final spk = libSegs[i].speaker;
      if (spk < 0) continue;
      final cur = longestPerCluster[spk];
      if (cur == null) {
        longestPerCluster[spk] = i;
        continue;
      }
      final curDur = libSegs[cur].t1 - libSegs[cur].t0;
      final candDur = libSegs[i].t1 - libSegs[i].t0;
      if (candDur > curDur) longestPerCluster[spk] = i;
    }

    if (longestPerCluster.isEmpty) return const {};

    final samples = audioData.samples;
    const sampleRate = 16000;
    const targetSeconds = 3.0;

    final out = <int, String>{};
    for (final entry in longestPerCluster.entries) {
      final spk = entry.key;
      final seg = libSegs[entry.value];
      final pcm = _slicePcm(samples, sampleRate, seg.t0, seg.t1, targetSeconds);
      if (pcm.isEmpty) continue;
      try {
        final (name, score) = await svc.matchSegment(pcm);
        if (name != null) {
          out[spk] = name;
          Log.instance.d('diarize', 'resolved speaker cluster', fields: {
            'cluster': spk,
            'name': name,
            'score': score.toStringAsFixed(3),
          });
        }
      } catch (e, st) {
        Log.instance
            .w('diarize', 'matchSegment failed for cluster $spk',
                error: e, stack: st);
      }
    }
    return out;
  }

  /// Carve a [targetSeconds]-long centred slice out of [samples] for
  /// the half-open time window `[t0, t1)`. Falls back to the full
  /// available slice when the segment is shorter than the target.
  Float32List _slicePcm(
    Float32List samples,
    int sampleRate,
    double t0,
    double t1,
    double targetSeconds,
  ) {
    final segStart = (t0 * sampleRate).round().clamp(0, samples.length);
    final segEnd = (t1 * sampleRate).round().clamp(segStart, samples.length);
    final segLen = segEnd - segStart;
    if (segLen <= 0) return Float32List(0);
    final targetLen = (targetSeconds * sampleRate).round();
    if (segLen <= targetLen) {
      return Float32List.fromList(samples.sublist(segStart, segEnd));
    }
    final pad = ((segLen - targetLen) / 2).floor();
    final start = segStart + pad;
    final end = start + targetLen;
    return Float32List.fromList(samples.sublist(start, end));
  }
}
