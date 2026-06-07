import 'dart:io';
import 'dart:typed_data';
import 'package:crispasr/crispasr.dart' as crispasr;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;

import 'audio_prefetch_service.dart';
import 'log_service.dart';
import 'settings_service.dart';

/// Singleton-per-ProviderScope. Lives alongside [AudioService] so
/// downstream services (BatchQueueNotifier, transcription pipeline)
/// can wire to it without depending on main.dart's provider graph.
final audioServiceProvider = Provider<AudioService>((ref) {
  // Read the prefetch service eagerly so loadAudioFile can probe its
  // cache before falling through to a synchronous decode (§5.23 Q2).
  final prefetch = ref.read(audioPrefetchServiceProvider);
  return AudioService(prefetch: prefetch);
});

class AudioService {
  AudioService({AudioPrefetchService? prefetch}) : _prefetch = prefetch;

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  final AudioPrefetchService? _prefetch;

  bool get isRecording => _isRecording;
  bool _isRecording = false;

  /// Record audio from microphone
  Future<String?> startRecording({SettingsService? settingsService}) async {
    try {
      if (await _recorder.hasPermission()) {
        final appDir = await getApplicationDocumentsDirectory();
        final fileName =
            'recording_${DateTime.now().millisecondsSinceEpoch}.wav';
        final filePath = path.join(appDir.path, fileName);

        final bitRate = settingsService != null
            ? (settingsService.audioQuality * 128000).toInt()
            : 128000;

        final config = RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: bitRate,
        );

        await _recorder.start(config, path: filePath);
        _isRecording = true;
        return filePath;
      }
      return null;
    } catch (e) {
      Log.instance.e('audio', 'Error starting recording', error: e);
      return null;
    }
  }

  /// Start a live PCM stream for stream-transcribe (Whisper sliding
  /// window). Each emitted Float32List is 16 kHz mono in [-1, 1],
  /// converted from the underlying int16 little-endian frames the
  /// `record` package delivers. Caller is responsible for `cancel()`
  /// on the returned subscription handle and calling [stopStreaming]
  /// to release the platform recorder.
  ///
  /// Why not pipe through a file? Because the file path requires a
  /// stop+read+decode round trip per chunk; the streaming PCM API
  /// hands us samples as soon as the OS buffers them so the live
  /// transcript heartbeat can be sub-second.
  Future<Stream<Float32List>?> startStreamingRecording() async {
    try {
      if (!await _recorder.hasPermission()) return null;
      const config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      );
      final byteStream = await _recorder.startStream(config);
      _isRecording = true;
      // Map int16 little-endian → Float32 in-stream so downstream
      // doesn't deal with the byte-level conversion.
      return byteStream.map((bytes) {
        final n = bytes.length ~/ 2;
        final out = Float32List(n);
        final bd = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length);
        for (var i = 0; i < n; i++) {
          out[i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
        }
        return out;
      });
    } catch (e) {
      Log.instance.e('audio', 'Error starting stream', error: e);
      return null;
    }
  }

  /// Stop the live PCM stream started by [startStreamingRecording].
  /// Idempotent — safe to call when not streaming.
  Future<void> stopStreaming() async {
    try {
      await _recorder.stop();
      _isRecording = false;
    } catch (e) {
      Log.instance.w('audio', 'Error stopping stream', error: e);
    }
  }

  /// Stop recording and return the file path
  Future<String?> stopRecording() async {
    try {
      final path = await _recorder.stop();
      _isRecording = false;
      return path;
    } catch (e) {
      Log.instance.e('audio', 'Error stopping recording', error: e);
      return null;
    }
  }

  /// Get current microphone amplitude
  Future<double> getAmplitude() async {
    try {
      final amp = await _recorder.getAmplitude();
      // Map -160..0 dB to 0..1 linear
      final linear = (amp.current + 160) / 160;
      return linear.clamp(0.0, 1.0);
    } catch (_) {
      return 0.0;
    }
  }

  /// Cheap header-only duration probe for batch ETA estimation
  /// (§5.23 Q1). Uses a throwaway [AudioPlayer] so we don't stomp the
  /// shared `_player` mid-playback. just_audio reads the container
  /// header to derive duration — no decode work — so this is sub-
  /// second on every supported format and platform.
  ///
  /// Returns null on any failure (unreadable file, unsupported
  /// codec, just_audio platform implementation missing). Callers
  /// (BatchQueueNotifier.enqueue) treat null as "we don't know,
  /// don't show an ETA" rather than failing the enqueue.
  Future<Duration?> probeDuration(File audioFile) async {
    AudioPlayer? probe;
    try {
      probe = AudioPlayer();
      // setFilePath returns the parsed duration when known (every
      // common container — wav/mp3/m4a/flac/ogg/opus — exposes it
      // in the header).
      final d = await probe.setFilePath(audioFile.path);
      if (d != null) return d;
      // Fallback: some platforms hand duration through the stream
      // shortly after setFilePath returns null. One short await is
      // enough; if it never arrives the file is genuinely
      // unprobable and we return null.
      return probe.duration;
    } catch (e, st) {
      Log.instance.d('audio', 'probeDuration failed',
          fields: {'file': path.basename(audioFile.path)},
          error: e,
          stack: st);
      return null;
    } finally {
      try {
        await probe?.dispose();
      } catch (_) {
        // Probe-only disposal failure isn't actionable.
      }
    }
  }

  /// Convert audio file to the required format for transcription.
  ///
  /// §5.23 Q2 fast path: consult [AudioPrefetchService] for an
  /// already-decoded sample buffer first. The drain loop calls
  /// `prefetch(nextPath)` while the current file is mid-
  /// transcription, so by the time we reach loadAudioFile for the
  /// next file the decode work has already happened in a worker
  /// isolate. Cache miss falls through to the synchronous FFI
  /// decode below — same behaviour as v0.4 single-file runs.
  Future<AudioData> loadAudioFile(File audioFile) async {
    try {
      // Load with just_audio to get duration and sample rate info.
      // This is also cheap (header-only) and runs in parallel with
      // the prefetch consume below.
      await _player.setFilePath(audioFile.path);
      final duration = _player.duration?.inMilliseconds ?? 0;

      WavData wavData;
      final prefetched = await _prefetch?.consume(audioFile.path);
      if (prefetched != null) {
        Log.instance.d('audio', 'load: served from prefetch',
            fields: {
              'file': path.basename(audioFile.path),
              'samples': prefetched.samples.length,
            });
        wavData = WavData(
          samples: prefetched.samples,
          sampleRate: prefetched.sampleRate,
          channels: 1, // decodeAudioFile always returns mono
        );
      } else {
        // Cache miss or prefetch failed — synchronous decode path.
        wavData = await _convertToWav(audioFile);
      }

      return AudioData(
        samples: wavData.samples,
        sampleRate: wavData.sampleRate,
        duration: Duration(milliseconds: duration),
        channels: wavData.channels,
      );
    } catch (e) {
      throw AudioProcessingException('Failed to load audio file: $e');
    }
  }

  /// Re-decode the audio file preserving stereo channels. Returns an
  /// [AudioData] with [rightChannel] populated when the source is
  /// stereo. Falls back to a mono-only [AudioData] when the stereo
  /// C-ABI symbol isn't available.
  Future<AudioData> loadAudioFileStereo(String filePath) async {
    try {
      final stereo = crispasr.decodeAudioFileStereo(filePath);
      final duration = stereo.left.length / stereo.sampleRate;
      return AudioData(
        samples: stereo.left,
        sampleRate: stereo.sampleRate,
        duration: Duration(milliseconds: (duration * 1000).round()),
        channels: stereo.sourceChannels,
        rightChannel: stereo.isStereo ? stereo.right : null,
      );
    } catch (e) {
      Log.instance.d('audio', 'stereo decode not available, falling back',
          error: e);
      return loadAudioFile(File(filePath));
    }
  }

  /// Download audio from URL
  Future<File> downloadAudioFromUrl(
    String url, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode != 200) {
        throw AudioDownloadException(
            'Failed to download audio: ${response.statusCode}');
      }

      final appDir = await getApplicationDocumentsDirectory();
      final fileName =
          'downloaded_${DateTime.now().millisecondsSinceEpoch}.${_getFileExtension(url)}';
      final file = File(path.join(appDir.path, fileName));

      await file.writeAsBytes(response.bodyBytes);
      return file;
    } catch (e) {
      throw AudioDownloadException('Failed to download audio: $e');
    }
  }

  /// Convert an arbitrary audio file to mono 16 kHz float32 PCM.
  Future<WavData> _convertToWav(File audioFile) async {
    int fileBytes = 0;
    try {
      fileBytes = await audioFile.length();
    } catch (_) {}
    final done = Log.instance.stopwatch('audio', msg: 'decode done', fields: {
      'file': path.basename(audioFile.path),
      'file_bytes': fileBytes
    });
    try {
      final decoded = crispasr.decodeAudioFile(audioFile.path);
      final seconds = decoded.samples.length / decoded.sampleRate;
      done(extra: {
        'via': 'ffi',
        'samples': decoded.samples.length,
        'sr': decoded.sampleRate,
        'duration_s': seconds.toStringAsFixed(2),
      });
      return WavData(
        samples: decoded.samples,
        sampleRate: decoded.sampleRate,
        channels: 1,
      );
    } on UnsupportedError catch (e) {
      Log.instance.w('audio', 'FFI decoder not available, falling back',
          fields: {'file': path.basename(audioFile.path)}, error: e);
    } catch (e, st) {
      Log.instance.w('audio', 'FFI decoder rejected, falling back',
          error: e,
          stack: st,
          fields: {
            'file': path.basename(audioFile.path),
            'file_bytes': fileBytes
          });
    }

    final wav = await _basicWavProcessing(audioFile);
    Log.instance.i('audio', 'decoded via Dart WAV parser', fields: {
      'file': path.basename(audioFile.path),
      'samples': wav.samples.length,
      'sr': wav.sampleRate,
      'channels': wav.channels,
    });
    return wav;
  }

  /// Basic WAV file processing fallback
  Future<WavData> _basicWavProcessing(File audioFile) async {
    final bytes = await audioFile.readAsBytes();
    final byteData = ByteData.sublistView(bytes);

    if (bytes.length < 12) {
      throw const AudioProcessingException('Invalid WAV file: too short');
    }

    final riff = String.fromCharCodes(bytes.sublist(0, 4));
    final wave = String.fromCharCodes(bytes.sublist(8, 12));

    if (riff != 'RIFF' || wave != 'WAVE') {
      // We only reach this fallback when the FFI decoder rejected the
      // file (miniaudio handles WAV / MP3 / FLAC / OGG). Tell the user
      // what's actually supported instead of "not a valid WAV file" —
      // the latter is technically true but unhelpful for someone who
      // tried to load an MP4 / M4A / AAC.
      throw const AudioProcessingException(
        'Unsupported audio format. CrisperWeaver decodes WAV, MP3, '
        'FLAC, and OGG natively. For M4A / AAC / MP4 / WMA, convert '
        'to one of those first (Voice Memos exports as M4A — re-export '
        'or use a converter).',
      );
    }

    int channels = 0;
    int sampleRate = 0;
    int bitsPerSample = 0;
    int dataOffset = -1;
    int dataSize = 0;

    int offset = 12;
    while (offset + 8 <= bytes.length) {
      final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = byteData.getUint32(offset + 4, Endian.little);
      offset += 8;

      if (chunkId == 'fmt ') {
        if (chunkSize < 16) {
          throw const AudioProcessingException('Invalid fmt chunk size');
        }
        channels = byteData.getUint16(offset + 2, Endian.little);
        sampleRate = byteData.getUint32(offset + 4, Endian.little);
        bitsPerSample = byteData.getUint16(offset + 14, Endian.little);
      } else if (chunkId == 'data') {
        dataOffset = offset;
        dataSize = chunkSize;
        if (channels > 0) break;
      }

      offset += chunkSize;
      if (chunkSize % 2 != 0) offset++;
    }

    if (dataOffset == -1) {
      throw const AudioProcessingException('No data chunk found in WAV file');
    }
    if (channels == 0) {
      throw const AudioProcessingException('No fmt chunk found in WAV file');
    }

    final actualDataSize = (bytes.length - dataOffset);
    final sizeToRead = dataSize < actualDataSize ? dataSize : actualDataSize;

    final samplesCount = sizeToRead ~/ (bitsPerSample ~/ 8);
    final samples = Float32List(samplesCount);

    if (bitsPerSample == 16) {
      for (int i = 0; i < samplesCount; i++) {
        final pos = dataOffset + i * 2;
        if (pos + 1 >= bytes.length) break;
        final raw = byteData.getInt16(pos, Endian.little);
        samples[i] = raw / 32768.0;
      }
    } else if (bitsPerSample == 32) {
      for (int i = 0; i < samplesCount; i++) {
        final pos = dataOffset + i * 4;
        if (pos + 3 >= bytes.length) break;
        samples[i] = byteData.getFloat32(pos, Endian.little);
      }
    } else {
      throw AudioProcessingException(
          'Unsupported bits per sample: $bitsPerSample');
    }

    return WavData(
      samples: samples,
      sampleRate: sampleRate,
      channels: channels,
    );
  }

  /// Play audio file for preview
  Future<void> playAudio(File audioFile) async {
    try {
      await _player.setFilePath(audioFile.path);
      await _player.play();
    } catch (e) {
      throw AudioPlaybackException('Failed to play audio: $e');
    }
  }

  /// Stop audio playback
  Future<void> stopPlayback() async {
    await _player.stop();
  }

  /// Get audio file information
  Future<AudioInfo> getAudioInfo(File audioFile) async {
    try {
      await _player.setFilePath(audioFile.path);

      return AudioInfo(
        duration: _player.duration ?? Duration.zero,
        fileName: path.basename(audioFile.path),
        fileSize: await audioFile.length(),
        filePath: audioFile.path,
      );
    } catch (e) {
      throw AudioProcessingException('Failed to get audio info: $e');
    }
  }

  String _getFileExtension(String url) {
    final uri = Uri.parse(url);
    final pathSegments = uri.pathSegments;
    if (pathSegments.isNotEmpty) {
      final fileName = pathSegments.last;
      final lastDot = fileName.lastIndexOf('.');
      if (lastDot != -1) {
        return fileName.substring(lastDot + 1);
      }
    }
    return 'mp3';
  }

  void dispose() {
    _recorder.dispose();
    _player.dispose();
  }
}

class AudioData {
  /// Mono PCM (or left channel for stereo sources).
  final Float32List samples;
  final int sampleRate;
  final Duration duration;
  final int channels;

  /// Right channel PCM — non-null when the source was stereo and
  /// decoded via [decodeAudioFileStereo]. Null for mono sources or
  /// when the stereo C-ABI wasn't available. When non-null, its
  /// length equals [samples.length].
  final Float32List? rightChannel;

  const AudioData({
    required this.samples,
    required this.sampleRate,
    required this.duration,
    required this.channels,
    this.rightChannel,
  });

  /// True when stereo channel data is available.
  bool get isStereo => rightChannel != null && channels >= 2;

  double get durationInSeconds => duration.inMilliseconds / 1000.0;
  int get totalSamples => samples.length;
}

class WavData {
  final Float32List samples;
  final int sampleRate;
  final int channels;

  const WavData({
    required this.samples,
    required this.sampleRate,
    required this.channels,
  });
}

class AudioInfo {
  final Duration duration;
  final String fileName;
  final int fileSize;
  final String filePath;

  const AudioInfo({
    required this.duration,
    required this.fileName,
    required this.fileSize,
    required this.filePath,
  });

  String get formattedDuration {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String get formattedFileSize {
    if (fileSize < 1024) {
      return '$fileSize B';
    } else if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }
}

class AudioProcessingException implements Exception {
  final String message;
  const AudioProcessingException(this.message);
  @override
  String toString() => 'AudioProcessingException: $message';
}

class AudioDownloadException implements Exception {
  final String message;
  const AudioDownloadException(this.message);
  @override
  String toString() => 'AudioDownloadException: $message';
}

class AudioPlaybackException implements Exception {
  final String message;
  const AudioPlaybackException(this.message);
  @override
  String toString() => 'AudioPlaybackException: $message';
}
