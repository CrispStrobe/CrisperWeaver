import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class MicrophoneDevice {
  const MicrophoneDevice(this.id, this.name);
  final String id;
  final String name;
  Map<String, String> toJson() => {'id': id, 'name': name};
}

/// AVFoundation emits its device list on stderr and exits nonzero by design.
List<MicrophoneDevice> parseAvfoundationDevices(String text) {
  var audio = false;
  final devices = <MicrophoneDevice>[];
  for (final line in const LineSplitter().convert(text)) {
    if (line.contains('AVFoundation audio devices:')) {
      audio = true;
      continue;
    }
    if (line.contains('AVFoundation video devices:')) audio = false;
    if (!audio) continue;
    final match = RegExp(r'\[(\d+)\] (.+)$').firstMatch(line);
    if (match != null) {
      devices.add(MicrophoneDevice(match[1]!, match[2]!.trim()));
    }
  }
  return devices;
}

MicrophoneDevice selectMicrophone(
    List<MicrophoneDevice> devices, String query) {
  final exact = devices.where((d) => d.id == query || d.name == query).toList();
  if (exact.length == 1) return exact.single;
  final matches = devices
      .where((d) => d.name.toLowerCase().contains(query.toLowerCase()))
      .toList();
  if (query.trim().isEmpty || matches.length != 1) {
    throw ArgumentError(
        'Microphone "$query" ${matches.isEmpty ? 'not found' : 'is ambiguous'}. '
        'Use live --list-devices and select its name or current ID.');
  }
  return matches.single;
}

Future<List<MicrophoneDevice>> listMicrophones(String ffmpeg) async {
  if (!Platform.isMacOS) {
    throw UnsupportedError(
        'Live microphone capture currently supports macOS AVFoundation.');
  }
  final result = await Process.run(ffmpeg, [
    '-hide_banner',
    '-f',
    'avfoundation',
    '-list_devices',
    'true',
    '-i',
    ''
  ]);
  final devices = parseAvfoundationDevices('${result.stderr}');
  if (devices.isEmpty) {
    throw StateError('No microphone inputs found: ${result.stderr}');
  }
  return devices;
}

/// Carries incomplete frames (including odd bytes) across pipe packets.
class Pcm16Framer {
  Pcm16Framer({this.frameSamples = 1600});
  final int frameSamples;
  Uint8List _pending = Uint8List(0);
  List<Float32List> add(List<int> bytes) {
    final combined = Uint8List(_pending.length + bytes.length)
      ..setAll(0, _pending)
      ..setAll(_pending.length, bytes);
    final result = <Float32List>[];
    final frameBytes = frameSamples * 2;
    var offset = 0;
    while (offset + frameBytes <= combined.length) {
      result.add(_decode(
          Uint8List.sublistView(combined, offset, offset + frameBytes)));
      offset += frameBytes;
    }
    _pending = Uint8List.fromList(combined.sublist(offset));
    return result;
  }

  Float32List finish() {
    if (_pending.length.isOdd) {
      throw const FormatException('Truncated PCM sample from capture.');
    }
    final result = _decode(_pending);
    _pending = Uint8List(0);
    return result;
  }

  Float32List _decode(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    return Float32List.fromList([
      for (var i = 0; i < bytes.length; i += 2)
        data.getInt16(i, Endian.little) / 32768.0,
    ]);
  }
}

/// Stream to disk, then repair the WAV header without retaining a whole talk.
class Pcm16WavSink {
  Pcm16WavSink(String path)
      : _file = File(path).openSync(mode: FileMode.write) {
    _file.writeFromSync(Uint8List(44));
  }
  final RandomAccessFile _file;
  int _bytes = 0;
  void add(List<int> bytes) {
    _file.writeFromSync(bytes);
    _bytes += bytes.length;
  }

  void close() {
    final h = Uint8List(44);
    final d = ByteData.sublistView(h);
    h.setAll(0, 'RIFF'.codeUnits);
    d.setUint32(4, 36 + _bytes, Endian.little);
    h.setAll(8, 'WAVEfmt '.codeUnits);
    d.setUint32(16, 16, Endian.little);
    d.setUint16(20, 1, Endian.little);
    d.setUint16(22, 1, Endian.little);
    d.setUint32(24, 16000, Endian.little);
    d.setUint32(28, 32000, Endian.little);
    d.setUint16(32, 2, Endian.little);
    d.setUint16(34, 16, Endian.little);
    h.setAll(36, 'data'.codeUnits);
    d.setUint32(40, _bytes, Endian.little);
    _file.setPositionSync(0);
    _file.writeFromSync(h);
    _file.closeSync();
  }
}
