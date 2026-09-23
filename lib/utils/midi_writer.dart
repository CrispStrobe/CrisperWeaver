import 'dart:typed_data';

/// One note for [MidiWriter]. Times are milliseconds from the start.
///
/// [program] is a General MIDI program 0-127, 128 for percussion, or -1
/// when the transcriber does not name an instrument (written as program 0,
/// Acoustic Grand Piano).
typedef MidiNote = ({
  int midi,
  double onMs,
  double offMs,
  int velocity,
  int program,
});

/// Writes a Standard MIDI File (format 1) from transcribed notes.
///
/// Track 0 carries the tempo; every instrument gets its own track and
/// channel, so a multi-instrument MT3 transcription opens in a DAW as one
/// part per instrument. Percussion (program 128) goes on channel 10 with no
/// program change, as General MIDI requires. At 120 bpm and 480 ticks per
/// quarter note one tick is 1.0417 ms, so note times survive to within a
/// millisecond.
class MidiWriter {
  MidiWriter._();

  static const int ticksPerQuarter = 480;
  static const int microsPerQuarter = 500000; // 120 bpm
  static const int _percussionChannel = 9; // channel 10, zero-based

  static int msToTicks(double ms) =>
      (ms * 1000 * ticksPerQuarter / microsPerQuarter).round();

  static Uint8List write(List<MidiNote> notes) {
    // Group by instrument, in first-appearance order for stable output.
    final byProgram = <int, List<MidiNote>>{};
    for (final n in notes) {
      final program = n.program < 0 ? 0 : n.program;
      byProgram.putIfAbsent(program, () => []).add(n);
    }

    // Every channel but 10 is melodic. Past 15 instruments channels are
    // reused; each program still has its own track and program change.
    const melodic = [0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15];
    final tracks = <List<int>>[_tempoTrack()];
    var melodicIndex = 0;
    for (final entry in byProgram.entries) {
      final channel = entry.key == 128
          ? _percussionChannel
          : melodic[melodicIndex++ % melodic.length];
      tracks.add(_noteTrack(entry.value, entry.key, channel));
    }

    final out = BytesBuilder();
    out.add(_chunk('MThd', [
      ..._u16(1), // format 1
      ..._u16(tracks.length),
      ..._u16(ticksPerQuarter),
    ]));
    for (final t in tracks) {
      out.add(_chunk('MTrk', t));
    }
    return out.toBytes();
  }

  static List<int> _tempoTrack() => [
        0x00, 0xFF, 0x51, 0x03, //
        (microsPerQuarter >> 16) & 0xFF,
        (microsPerQuarter >> 8) & 0xFF,
        microsPerQuarter & 0xFF,
        0x00, 0xFF, 0x2F, 0x00, // end of track
      ];

  static List<int> _noteTrack(List<MidiNote> notes, int program, int channel) {
    // (tick, isOn, note, velocity). Offs sort before ons at the same tick so
    // a repeated note is released before it is struck again.
    final events = <(int, bool, int, int)>[];
    for (final n in notes) {
      final key = n.midi.clamp(0, 127);
      final on = msToTicks(n.onMs);
      var off = msToTicks(n.offMs);
      if (off <= on) off = on + 1;
      // Velocity 0 on a note-on means note-off; keep a real note audible.
      events.add((on, true, key, n.velocity.clamp(1, 127)));
      events.add((off, false, key, 0));
    }
    events.sort((a, b) {
      final t = a.$1.compareTo(b.$1);
      if (t != 0) return t;
      if (a.$2 != b.$2) return a.$2 ? 1 : -1;
      return a.$3.compareTo(b.$3);
    });

    final body = <int>[];
    if (channel != _percussionChannel) {
      body.addAll([0x00, 0xC0 | channel, program & 0x7F]);
    }
    var last = 0;
    for (final (tick, isOn, key, vel) in events) {
      body.addAll(_vlq(tick - last));
      last = tick;
      body.addAll(isOn
          ? [0x90 | channel, key, vel]
          : [0x80 | channel, key, 0x40]);
    }
    body.addAll([0x00, 0xFF, 0x2F, 0x00]);
    return body;
  }

  static List<int> _chunk(String id, List<int> body) =>
      [...id.codeUnits, ..._u32(body.length), ...body];

  static List<int> _u16(int v) => [(v >> 8) & 0xFF, v & 0xFF];

  static List<int> _u32(int v) =>
      [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];

  /// MIDI variable-length quantity: 7 bits per byte, high bit = more.
  static List<int> _vlq(int v) {
    final bytes = <int>[v & 0x7F];
    v >>= 7;
    while (v > 0) {
      bytes.insert(0, (v & 0x7F) | 0x80);
      v >>= 7;
    }
    return bytes;
  }
}
