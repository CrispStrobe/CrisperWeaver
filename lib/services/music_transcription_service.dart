import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../native/crispasr_import.dart' as crispasr;
import '../utils/audio_utils.dart';
import '../utils/midi_writer.dart';
import 'audio_service.dart';
import 'log_service.dart';
import 'model_service.dart';

/// Notes transcribed from one recording, ready for [MidiWriter].
class MusicTranscription {
  final List<MidiNote> notes;
  final String backend;
  final Duration elapsed;

  const MusicTranscription({
    required this.notes,
    required this.backend,
    required this.elapsed,
  });

  /// General MIDI programs present, in first-appearance order. Empty when
  /// the model does not name instruments (every note's program is -1).
  List<int> get programs =>
      {for (final n in notes) if (n.program >= 0) n.program}.toList();

  double get lastOffSeconds => notes.isEmpty
      ? 0
      : notes.map((n) => n.offMs).reduce((a, b) => a > b ? a : b) / 1000;

  Uint8List toMidi() => MidiWriter.write(notes);
}

/// Audio → note events through CrispASR's structured piano ABI
/// (`pianoNotesWithPrograms`), which every note-transcription backend
/// implements: basic-pitch, mt3, piano-transcription, onsets-and-frames
/// and hft-transformer.
class MusicTranscriptionService {
  MusicTranscriptionService({
    required this.modelService,
    required this.audioService,
  });

  final ModelService modelService;
  final AudioService audioService;

  static const backends = <String>{
    'basic-pitch',
    'mt3',
    'piano-transcription',
    'onsets-and-frames',
    'hft-transformer',
  };

  Future<MusicTranscription> transcribe({
    required String audioPath,
    required String modelName,
  }) async {
    final backend = modelService.lookupDefinition(modelName)?.backend;
    if (backend == null || !backends.contains(backend)) {
      throw ArgumentError.value(modelName, 'modelName', 'not a music model');
    }
    final modelPath = await modelService.getWhisperCppModelPath(modelName);
    if (modelPath == null || !await File(modelPath).exists()) {
      throw StateError('model not downloaded: $modelName');
    }
    final audio = await audioService.loadAudioFile(File(audioPath));
    final samples = audio.samples;
    final sampleRate = audio.sampleRate;

    final sw = Stopwatch()..start();
    // A synchronous FFI call that can run for minutes (MT3, and
    // piano-transcription on CPU), so it goes off the UI isolate.
    final notes = await Isolate.run(
        () => runModel(modelPath, backend, samples, sampleRate));
    sw.stop();
    Log.instance.i('music', 'transcribed', fields: {
      'backend': backend,
      'notes': notes.length,
      'ms': sw.elapsedMilliseconds,
    });
    return MusicTranscription(
        notes: notes, backend: backend, elapsed: sw.elapsed);
  }

  /// Open [modelPath], bring [samples] to the model's own rate (Basic Pitch
  /// runs at 22.05 kHz, the others at 16 kHz) and return its notes sorted
  /// by onset. Static so it can run in an isolate.
  static List<MidiNote> runModel(
      String modelPath, String backend, Float32List samples, int sampleRate,
      {String? libPath}) {
    final s = crispasr.CrispasrSession.open(modelPath,
        backend: backend, libPath: libPath);
    try {
      final rate = s.pianoSampleRate;
      final pcm = (rate <= 0 || rate == sampleRate)
          ? samples
          : AudioUtils.resample(samples, sampleRate, rate);
      final notes = [
        for (final n in s.pianoNotesWithPrograms(pcm))
          (
            midi: n.midi,
            onMs: n.onMs,
            offMs: n.offMs,
            velocity: n.velocity,
            program: n.program,
          ),
      ]..sort((a, b) => a.onMs.compareTo(b.onMs));
      return notes;
    } finally {
      s.close();
    }
  }
}
