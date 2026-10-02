import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../constants/build_flavor.dart';
import '../services/browser_speech_client.dart';
import '../services/spread_spectrum_watermark.dart';
import '../utils/marked_wav.dart';
import '../widgets/root_aware_back_leading.dart';

/// Local browser TTS. Uses the same CrispASR synthesis/marking surface as
/// native apps, with blob playback/download rather than native file paths.
class BrowserSynthesizeScreen extends StatefulWidget {
  const BrowserSynthesizeScreen({super.key});
  @override
  State<BrowserSynthesizeScreen> createState() =>
      _BrowserSynthesizeScreenState();
}

class _BrowserSynthesizeScreenState extends State<BrowserSynthesizeScreen> {
  final _text = TextEditingController();
  final _player = AudioPlayer();
  late final _client = BrowserSpeechClient('crispasr',
      allowDownloads: BuildFlavor.allowModelDownloads);
  bool _busy = false;
  double _progress = 0;
  String? _error, _url;
  Future<void> _synthesize() async {
    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
    });
    try {
      final result = await _client.request('synthesize', {'text': _text.text},
          onProgress: (value) {
        if (mounted) setState(() => _progress = value);
      }) as Map;
      if (!mounted) return;
      var audio = result['audio'] as Float32List;
      if (SpreadSpectrumWatermark.detect(audio) <
          SpreadSpectrumWatermark.confidenceFloor) {
        audio = SpreadSpectrumWatermark.embed(audio);
      }
      final bytes = MarkedWav.encode(audio, result['sampleRate'] as int,
          generatorVersion: 'CrispASR-WASM',
          modelName: 'kokoro-82m-q8_0',
          voiceId: 'af_heart');
      if (_url != null) BrowserSpeechClient.revokeUrl(_url!);
      _url = BrowserSpeechClient.audioUrl(bytes);
      if (mounted) setState(() {});
      await _player.setUrl(_url!);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _client.dispose();
    _text.dispose();
    _player.dispose();
    if (_url != null) BrowserSpeechClient.revokeUrl(_url!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            leading: rootAwareBackLeading(context),
            title: const Text('Local speech synthesis')),
        body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('CrispASR WASM · Kokoro · English voice af_heart'),
              const SizedBox(height: 12),
              const Text(
                  'Speech is generated in your browser. First use downloads and caches model weights, the voice, and a pronunciation dictionary. Text is not uploaded. Output is AI-generated and carries audio markings.'),
              const SizedBox(height: 20),
              TextField(
                  controller: _text,
                  minLines: 4,
                  maxLines: 8,
                  maxLength: 1000,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                      labelText: 'Text to speak',
                      border: OutlineInputBorder())),
              if (_busy) ...[
                LinearProgressIndicator(
                    value: _progress > 0 && _progress < 1 ? _progress : null),
                const Text('Downloading model or generating speech locally…')
              ],
              if (_error != null)
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              Wrap(spacing: 12, children: [
                FilledButton(
                    onPressed: _busy ? null : _synthesize,
                    child: const Text('Generate speech')),
                if (_busy)
                  TextButton(
                      onPressed: () {
                        _client.cancel();
                      },
                      child: const Text('Cancel')),
                if (_url != null) ...[
                  OutlinedButton(
                      onPressed: () => _player.play(),
                      child: const Text('Play AI-generated audio')),
                  OutlinedButton(
                      onPressed: () => BrowserSpeechClient.download(
                          _url!, 'crisperweaver-ai-speech.wav'),
                      child: const Text('Download WAV')),
                ],
              ]),
            ])),
      );
}
