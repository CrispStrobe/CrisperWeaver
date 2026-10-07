import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:crisper_weaver/cli/microphone_capture.dart';

void main() {
  const output = '''[AVFoundation indev @ 0x123] AVFoundation video devices:
[AVFoundation indev @ 0x123] [0] FaceTime HD Camera
[AVFoundation indev @ 0x123] AVFoundation audio devices:
[AVFoundation indev @ 0x123] [0] Sennheiser SP 20 for Lync
[AVFoundation indev @ 0x123] [1] MacBook Air Microphone
Error opening input file .''';
  test('lists audio inputs without confusing cameras and microphones', () {
    final d = parseAvfoundationDevices(output);
    expect(d.map((d) => d.name), ['Sennheiser SP 20 for Lync', 'MacBook Air Microphone']);
    expect(selectMicrophone(d, 'sennheiser').id, '0');
    expect(selectMicrophone(d, '1').name, 'MacBook Air Microphone');
    expect(() => selectMicrophone(d, 'missing'), throwsArgumentError);
    expect(() => selectMicrophone(d, ''), throwsArgumentError);
    expect(() => selectMicrophone([...d, const MicrophoneDevice('2', 'Sennheiser other')], 'sennheiser'), throwsArgumentError);
  });
  test('odd pipe boundaries preserve every PCM sample and final tail', () {
    final f = Pcm16Framer(frameSamples: 2);
    expect(f.add([0]), isEmpty);
    final first = f.add([128, 255, 127, 0]);
    expect(first.single, [-1, 32767 / 32768]);
    expect(f.add([64]), isEmpty);
    expect(f.finish(), [.5]);
    expect(f.finish(), isEmpty);
    f.add([1]);
    expect(() => f.finish(), throwsFormatException);
  });
  test('saved WAV header matches streamed PCM, including a partial frame', () {
    final dir = Directory.systemTemp.createTempSync('cw_mic_wav_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/capture.wav';
    final sink = Pcm16WavSink(path);
    sink.add([0, 128, 255]); sink.add([127, 0, 64]); sink.close();
    final bytes = File(path).readAsBytesSync();
    final header = ByteData.sublistView(bytes);
    expect(bytes.length, 50);
    expect(header.getUint32(4, Endian.little), 42);
    expect(header.getUint32(24, Endian.little), 16000);
    expect(header.getUint32(40, Endian.little), 6);
    expect(bytes.sublist(44), [0, 128, 255, 127, 0, 64]);
  });
}
