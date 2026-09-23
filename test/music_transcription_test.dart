// Audio → MIDI: the Standard MIDI File writer, the catalogue entries, and
// an opt-in end-to-end run against a real model.
//
// Opt-in live check (synthesises its own C-major clip, so no fixture):
//   CRISPASR_LIB=/path/libcrispasr.so \
//   CRISPASR_TEST_BASIC_PITCH_MODEL=/path/basic-pitch-f16.gguf \
//   flutter test --tags slow test/music_transcription_test.dart

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crisper_weaver/services/model_catalog.dart';
import 'package:crisper_weaver/services/music_transcription_service.dart';
import 'package:crisper_weaver/utils/gm_programs.dart';
import 'package:crisper_weaver/utils/midi_writer.dart';
import 'package:flutter_test/flutter_test.dart';

MidiNote note(int midi, double on, double off,
        {int velocity = 80, int program = -1}) =>
    (midi: midi, onMs: on, offMs: off, velocity: velocity, program: program);

/// Minimal SMF reader: returns the header fields and, per track, the
/// channel events as (absoluteTick, status, data1, data2).
({int format, int nTracks, int division, List<List<(int, int, int, int)>> tracks})
    parseSmf(Uint8List b) {
  var i = 0;
  String id() => String.fromCharCodes(b.sublist(i, i += 4));
  int u32() => (b[i++] << 24) | (b[i++] << 16) | (b[i++] << 8) | b[i++];
  int u16() => (b[i++] << 8) | b[i++];
  expect(id(), 'MThd');
  expect(u32(), 6);
  final format = u16(), nTracks = u16(), division = u16();
  final tracks = <List<(int, int, int, int)>>[];
  for (var t = 0; t < nTracks; t++) {
    expect(id(), 'MTrk');
    final end = u32() + i;
    final events = <(int, int, int, int)>[];
    var tick = 0;
    while (i < end) {
      var delta = 0;
      int c;
      do {
        c = b[i++];
        delta = (delta << 7) | (c & 0x7F);
      } while (c & 0x80 != 0);
      tick += delta;
      final status = b[i++];
      if (status == 0xFF) {
        i++; // meta type
        final len = b[i++];
        i += len;
      } else if (status & 0xF0 == 0xC0) {
        events.add((tick, status, b[i++], 0));
      } else {
        events.add((tick, status, b[i++], b[i++]));
      }
    }
    tracks.add(events);
  }
  return (format: format, nTracks: nTracks, division: division, tracks: tracks);
}

void main() {
  group('MidiWriter', () {
    test('format 1: tempo track plus one note track, 480 ticks/quarter', () {
      final smf = parseSmf(MidiWriter.write([note(60, 0, 500)]));
      expect(smf.format, 1);
      expect(smf.nTracks, 2);
      expect(smf.division, 480);
      expect(smf.tracks[0], isEmpty); // tempo meta only
    });

    test('an unnamed instrument is written as piano on channel 1', () {
      final events = parseSmf(MidiWriter.write([note(60, 0, 500)])).tracks[1];
      expect(events.first, (0, 0xC0, 0, 0)); // program change → 0
      expect(events[1], (0, 0x90, 60, 80));
      // 500 ms at 120 bpm is exactly one quarter note.
      expect(events[2], (480, 0x80, 60, 0x40));
    });

    test('one track and channel per instrument; drums on channel 10', () {
      final smf = parseSmf(MidiWriter.write([
        note(60, 0, 100, program: 0),
        note(36, 0, 100, program: 128),
        note(40, 0, 100, program: 33),
      ]));
      expect(smf.nTracks, 4);
      final piano = smf.tracks[1], drums = smf.tracks[2], bass = smf.tracks[3];
      expect(piano.first, (0, 0xC0, 0, 0));
      // Percussion: no program change, channel 10 (0x9 zero-based).
      expect(drums.first.$2, 0x99);
      expect(drums.any((e) => e.$2 & 0xF0 == 0xC0), isFalse);
      expect(bass.first, (0, 0xC1, 33, 0));
    });

    test('a note released and struck again at the same tick stays audible',
        () {
      final events = parseSmf(MidiWriter.write(
              [note(60, 0, 500), note(60, 500, 1000)]))
          .tracks[1]
          .skip(1) // program change
          .toList();
      expect(events.map((e) => (e.$1, e.$2)).toList(), [
        (0, 0x90),
        (480, 0x80), // off first ...
        (480, 0x90), // ... then on again
        (960, 0x80),
      ]);
    });

    test('zero-length notes and velocity 0 still produce a real note', () {
      final events =
          parseSmf(MidiWriter.write([note(60, 100, 100, velocity: 0)]))
              .tracks[1];
      final on = events.firstWhere((e) => e.$2 == 0x90);
      final off = events.firstWhere((e) => e.$2 == 0x80);
      expect(on.$4, 1); // velocity 0 on a note-on would mean "off"
      expect(off.$1, greaterThan(on.$1));
    });

    test('long gaps use multi-byte delta times', () {
      // 60 s → 57600 ticks, which needs a three-byte VLQ.
      final events =
          parseSmf(MidiWriter.write([note(60, 60000, 60500)])).tracks[1];
      expect(events[1].$1, 57600);
    });
  });

  test('GM names: programs, drums, and the no-instrument sentinel', () {
    expect(gmProgramNames, hasLength(128));
    expect(gmProgramName(0), 'Acoustic Grand Piano');
    expect(gmProgramName(40), 'Violin');
    expect(gmProgramName(128), 'Drums');
    expect(gmProgramName(-1), isNull);
  });

  test('catalogue: every music model is kind music and routable', () {
    final music = ModelCatalog.crispasrBackendModels.values
        .where((m) => m.kind == ModelKind.music)
        .toList();
    expect(music.map((m) => m.backend).toSet(),
        MusicTranscriptionService.backends);
    for (final m in music) {
      expect(m.isNonCommercial, isFalse, reason: m.name);
    }
  });

  test('MusicTranscription summary fields', () {
    final r = MusicTranscription(
      notes: [
        note(60, 0, 900, program: 4),
        note(64, 100, 2500, program: 4),
        note(36, 0, 100, program: 128),
        note(67, 0, 100),
      ],
      backend: 'mt3',
      elapsed: Duration.zero,
    );
    expect(r.programs, [4, 128]); // -1 is "no instrument", not listed
    expect(r.lastOffSeconds, 2.5);
  });

  final libPath = Platform.environment['CRISPASR_LIB'];
  final model = Platform.environment['CRISPASR_TEST_BASIC_PITCH_MODEL'];

  test('Basic Pitch transcribes a synthesised C-major clip (opt-in)',
      tags: ['slow'], () {
    // C4 E4 G4 C5 in sequence, then a C-E-G chord: five harmonics with an
    // exponential decay, 16 kHz — runModel resamples to Basic Pitch's 22.05.
    const sr = 16000;
    const events = [
      (60, 0.0, 0.6), (64, 0.7, 0.6), (67, 1.4, 0.6), (72, 2.1, 0.6), //
      (60, 3.0, 1.2), (64, 3.0, 1.2), (67, 3.0, 1.2),
    ];
    final pcm = Float32List((sr * 4.8).round());
    for (final (midi, t0, dur) in events) {
      final f = 440 * math.pow(2, (midi - 69) / 12);
      final s0 = (t0 * sr).round();
      for (var i = 0; i < (dur * sr).round() && s0 + i < pcm.length; i++) {
        final t = i / sr;
        final env = math.exp(-3 * t) * math.min(1, t * 200);
        var v = 0.0;
        for (var h = 1; h <= 5; h++) {
          v += (0.6 / h) * math.sin(2 * math.pi * f * h * t);
        }
        pcm[s0 + i] += 0.25 * env * v;
      }
    }
    final notes = MusicTranscriptionService.runModel(
        model!, 'basic-pitch', pcm, sr,
        libPath: libPath);
    // Every played note is found near its onset. Basic Pitch may add a
    // quiet harmonic, which is why this is a containment check.
    for (final (midi, t0, _) in events) {
      expect(
          notes.any((n) => n.midi == midi && (n.onMs - t0 * 1000).abs() < 150),
          isTrue,
          reason: 'missing $midi at ${t0}s: $notes');
    }
    final smf = parseSmf(MidiWriter.write(notes));
    expect(smf.nTracks, 2);
  },
      skip: (libPath == null || model == null)
          ? 'set CRISPASR_LIB + CRISPASR_TEST_BASIC_PITCH_MODEL'
          : null);
}
