// SystemAudioCaptureService — PLAN §5.1.1 system-audio capture.
//
// "Transcribe what's playing in Zoom / YouTube / a podcast app."
// Cross-platform interface with three implementation strategies:
//
//   • **macOS 13+**: native via MethodChannel +
//     ScreenCaptureKit (see `macos/Runner/SystemAudioCapture.swift`).
//     Bidirectional protocol; native side handles resampling +
//     mono mix; Dart receives 16 kHz mono Float32 frames.
//   • **Linux**: subprocess to `parec` (PulseAudio's record tool;
//     also provided by pipewire-pulse on Pipewire-based distros).
//     Captures from the default sink's `.monitor` source, asking
//     parec to emit raw 16 kHz mono float32-le PCM directly so we
//     don't have to resample in Dart. Ships with `pulseaudio-utils`
//     on every major Linux distro out of the box.
//   • **Windows**: subprocess to `ffmpeg` with the
//     `-f dshow / -i audio=...` (or `-f wasapi`) loopback path.
//     Requires the user to have ffmpeg on PATH — we surface a
//     clean error when it's not. A native WASAPI plugin would
//     remove that dependency at the cost of a custom Windows
//     plugin (deferred follow-up).
//   • **iOS**: permanently unsupported — Apple sandbox forbids
//     system audio capture entirely.
//   • **Android**: not wired yet (MediaProjection — separate
//     piece of work with its own UI permission flow).
//
// Cross-platform: the `start() → Stream<Float32List>` API is
// identical on every supported platform; the implementation
// chooses subprocess vs MethodChannel internally. Unsupported
// platforms (iOS, Android in v1, Windows without ffmpeg, Linux
// without parec) throw [SystemAudioUnsupportedException].
//
// Permission model: macOS prompts for Screen Recording permission
// (TCC) on first start() call. Linux + Windows just spawn the
// subprocess — the OS handles any virtual-microphone permission
// requirements via the subprocess's own UI. Caller should
// surface a localized hint for `permission_denied` separately
// from `unsupported` so the user knows to open System Settings
// vs. install a missing tool.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'log_service.dart';
import '../utils/platform_utils.dart' as plat;

const MethodChannel _control =
    MethodChannel('crisperweaver/system_audio_capture');
const EventChannel _stream =
    EventChannel('crisperweaver/system_audio_capture/stream');

/// Thrown when system audio capture isn't supported on the active
/// platform. Callers should disable the toggle in the UI.
class SystemAudioUnsupportedException implements Exception {
  SystemAudioUnsupportedException(this.message);
  final String message;
  @override
  String toString() => 'SystemAudioUnsupportedException: $message';
}

/// Thrown when the user has not granted Screen Recording permission
/// (macOS) or the equivalent on other platforms.
class SystemAudioPermissionException implements Exception {
  SystemAudioPermissionException(this.message);
  final String message;
  @override
  String toString() => 'SystemAudioPermissionException: $message';
}

class SystemAudioCaptureService {
  SystemAudioCaptureService();

  StreamSubscription<dynamic>? _activeSub;
  StreamController<Float32List>? _activeController;
  // Linux / Windows subprocess capture: the spawned ffmpeg / parec
  // process and the subscription that pumps its stdout into the
  // controller's Float32List sink. Kept null on macOS (which
  // uses the native MethodChannel path instead).
  Process? _subprocess;
  StreamSubscription<List<int>>? _subprocessStdoutSub;
  // Quick probe of which subprocess tool we'll use, set by the
  // first isSupported() call so the start() path doesn't have to
  // re-which the tool name. Null until the probe has run.
  String? _linuxTool; // 'parec' (PulseAudio) — only one supported in v1
  String? _windowsTool; // 'ffmpeg' (WASAPI loopback via dshow / wasapi)

  /// Quick capability probe — returns true when the active platform
  /// can capture system audio. UI uses this to enable / disable the
  /// "Capture system audio" toggle without having to attempt a
  /// start() and catch the error.
  ///
  /// Platform results:
  ///   • macOS → native MethodChannel `isSupported` (returns
  ///     false on macOS < 13 because SCStream audio capture
  ///     needs macOS 13+).
  ///   • Android → native MethodChannel `isSupported` (returns
  ///     false on Android < 10 because AudioPlaybackCaptureConfig
  ///     needs API 29+). System notification appears while
  ///     capturing (Android requirement).
  ///   • Linux → true when `parec` is on PATH (PulseAudio or
  ///     pipewire-pulse). Result cached for the next start().
  ///   • Windows → true when `ffmpeg` is on PATH.
  ///   • iOS → always false (Apple sandbox restriction).
  Future<bool> isSupported() async {
    if (plat.isIOS) return false;
    if (plat.isMacOS || plat.isAndroid) {
      try {
        final ok = await _control.invokeMethod<bool>('isSupported') ?? false;
        return ok;
      } catch (e) {
        Log.instance.d('sysaudio', 'isSupported probe failed: $e');
        return false;
      }
    }
    if (plat.isLinux) {
      _linuxTool ??= await _whichOnPath('parec');
      return _linuxTool != null;
    }
    if (plat.isWindows) {
      _windowsTool ??= await _whichOnPath('ffmpeg');
      return _windowsTool != null;
    }
    return false;
  }

  /// Cross-platform `which / where` for the [tool] binary. Returns
  /// the absolute path on success, null when the tool isn't on
  /// PATH or the probe fails. Used by the subprocess-capture
  /// platforms (Linux + Windows) to detect tool availability
  /// before start() throws.
  Future<String?> _whichOnPath(String tool) async {
    try {
      final cmd = plat.isWindows ? 'where' : 'which';
      final r = await Process.run(cmd, [tool], runInShell: false);
      if (r.exitCode != 0) return null;
      final out = (r.stdout as String).trim();
      if (out.isEmpty) return null;
      // `where` on Windows returns newline-separated matches; take
      // the first. `which` always returns exactly one line.
      return out.split('\n').first.trim();
    } catch (_) {
      return null;
    }
  }

  /// Start the capture. Returns a stream of 16 kHz mono Float32List
  /// PCM chunks. Caller listens; calling [stop] closes the stream.
  ///
  /// Throws [SystemAudioUnsupportedException] when the platform
  /// doesn't support it (iOS / Android v1, macOS < 13, Linux
  /// without parec, Windows without ffmpeg), and
  /// [SystemAudioPermissionException] when the user has declined
  /// the OS-level capture permission (currently only macOS
  /// surfaces a typed permission denial; Linux + Windows let the
  /// subprocess fail with whatever exit code their underlying
  /// stack produces).
  Future<Stream<Float32List>> start() async {
    if (plat.isIOS) {
      throw SystemAudioUnsupportedException(
          'System audio capture is not supported on iOS — Apple '
          'sandbox restriction.');
    }
    if (_activeController != null) {
      // Already running — reuse the existing stream. Cheap idempotency.
      return _activeController!.stream;
    }

    if (plat.isMacOS || plat.isAndroid) {
      // Same MethodChannel + EventChannel protocol. macOS uses
      // ScreenCaptureKit, Android uses MediaProjection — both
      // deliver 16 kHz mono Float32 PCM through the same wire.
      return _startNativeChannel();
    }
    if (plat.isLinux) return _startLinuxParec();
    if (plat.isWindows) return _startWindowsFfmpeg();
    throw SystemAudioUnsupportedException(
        'Unknown platform: ${plat.operatingSystem}');
  }

  /// Native MethodChannel + EventChannel path. macOS:
  /// ScreenCaptureKit (`macos/Runner/SystemAudioCapture.swift`).
  /// Android: MediaProjection + foreground service
  /// (`android/.../SystemAudioCaptureForegroundService.kt`).
  Future<Stream<Float32List>> _startNativeChannel() async {
    try {
      final ok = await _control.invokeMethod<bool>('start') ?? false;
      if (!ok) {
        throw SystemAudioUnsupportedException(
            'native start() returned false — see platform log for details');
      }
    } on PlatformException catch (e) {
      switch (e.code) {
        case 'permission_denied':
          throw SystemAudioPermissionException(e.message ??
              'System audio capture permission denied');
        case 'os_too_old':
          throw SystemAudioUnsupportedException(e.message ??
              'OS version too old for system audio capture');
        case 'unsupported':
        default:
          throw SystemAudioUnsupportedException(
              e.message ?? 'native side declined to start');
      }
    }

    final controller = StreamController<Float32List>.broadcast();
    _activeController = controller;

    _activeSub = _stream.receiveBroadcastStream().listen(
      (event) {
        if (event is Uint8List) {
          final f = event.buffer
              .asFloat32List(event.offsetInBytes, event.length ~/ 4);
          if (controller.isClosed) return;
          controller.add(f);
        } else if (event is Float32List) {
          if (controller.isClosed) return;
          controller.add(event);
        }
      },
      onError: (Object e, StackTrace st) {
        Log.instance.w('sysaudio', 'stream error', error: e, stack: st);
        if (!controller.isClosed) controller.addError(e, st);
      },
      onDone: () {
        if (!controller.isClosed) controller.close();
      },
    );

    Log.instance.i('sysaudio',
        'capture started (${plat.operatingSystem} native)');
    return controller.stream;
  }

  /// Linux — `parec` subprocess against the default sink's
  /// `.monitor` source, asking for 16 kHz mono float32-le PCM
  /// directly so we don't have to resample in Dart.
  Future<Stream<Float32List>> _startLinuxParec() async {
    _linuxTool ??= await _whichOnPath('parec');
    final parec = _linuxTool;
    if (parec == null) {
      throw SystemAudioUnsupportedException(
          'parec not found on PATH. Install `pulseaudio-utils` '
          '(Ubuntu/Debian) or `pipewire-pulse` (Fedora) to enable '
          'system audio capture.');
    }
    return _startSubprocessCapture(
      executable: parec,
      arguments: [
        // Default sink's monitor source — captures whatever's
        // currently playing through the system mixer.
        '--device=@DEFAULT_SINK@.monitor',
        '--rate=16000',
        '--channels=1',
        '--format=float32le',
        // --raw is the default for parec; pass explicitly to be
        // bulletproof against alias differences.
        '--raw',
        // No latency cap — parec uses sensible defaults.
      ],
      label: 'parec',
    );
  }

  /// Windows — `ffmpeg` subprocess via the `audio=virtual-audio-capturer`
  /// dshow source. Requires the user to have ffmpeg on PATH; we
  /// surface a typed "missing tool" error if not.
  Future<Stream<Float32List>> _startWindowsFfmpeg() async {
    _windowsTool ??= await _whichOnPath('ffmpeg');
    final ffmpeg = _windowsTool;
    if (ffmpeg == null) {
      throw SystemAudioUnsupportedException(
          'ffmpeg not found on PATH. Install ffmpeg (e.g. '
          '`winget install Gyan.FFmpeg` or `choco install ffmpeg`) '
          'to enable system audio capture.');
    }
    return _startSubprocessCapture(
      executable: ffmpeg,
      arguments: [
        // WASAPI loopback: captures the system default output
        // ("what you hear"). No virtual audio device install
        // needed — ffmpeg's `wasapi` muxer handles it natively
        // from FFmpeg 5+. The `audio="..."` quoting is required.
        '-loglevel', 'error',
        '-f', 'wasapi',
        '-i', 'default',
        '-ac', '1',
        '-ar', '16000',
        '-f', 'f32le',
        '-',
      ],
      label: 'ffmpeg',
    );
  }

  /// Shared subprocess driver — spawns [executable] with
  /// [arguments], pipes stdout into a broadcast Float32List
  /// stream. Stderr is logged but not surfaced as stream errors
  /// (most ffmpeg / parec stderr is informational, not fatal).
  Future<Stream<Float32List>> _startSubprocessCapture({
    required String executable,
    required List<String> arguments,
    required String label,
  }) async {
    final controller = StreamController<Float32List>.broadcast();
    _activeController = controller;

    Process proc;
    try {
      proc = await Process.start(executable, arguments,
          runInShell: false);
    } catch (e) {
      _activeController = null;
      throw SystemAudioUnsupportedException(
          'Failed to spawn $label: $e');
    }
    _subprocess = proc;

    // PCM stdout: raw float32-le bytes. We buffer odd-length
    // residues across `add()` calls so a Float32List reinterpret
    // is always 4-byte aligned.
    final residue = BytesBuilder();
    _subprocessStdoutSub = proc.stdout.listen(
      (chunk) {
        if (controller.isClosed) return;
        residue.add(chunk);
        final all = residue.takeBytes();
        final aligned = all.length - (all.length % 4);
        if (aligned == 0) {
          // not enough bytes yet — keep residue
          residue.add(all);
          return;
        }
        final usable = Uint8List.fromList(all.sublist(0, aligned));
        final rest = all.sublist(aligned);
        if (rest.isNotEmpty) residue.add(rest);
        final f =
            usable.buffer.asFloat32List(usable.offsetInBytes, aligned ~/ 4);
        controller.add(f);
      },
      onError: (Object e, StackTrace st) {
        Log.instance.w('sysaudio', '$label stdout error',
            error: e, stack: st);
        if (!controller.isClosed) controller.addError(e, st);
      },
      onDone: () {
        if (!controller.isClosed) controller.close();
      },
    );

    // Drain stderr to the log so a misconfigured subprocess
    // doesn't hang on a full pipe.
    proc.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (line.trim().isEmpty) return;
      Log.instance.d('sysaudio', '$label stderr: $line');
    });

    // When the subprocess exits, close the stream.
    proc.exitCode.then((code) {
      Log.instance.i('sysaudio', '$label exited',
          fields: {'code': code});
      if (!controller.isClosed) controller.close();
    });

    Log.instance.i('sysaudio', 'capture started ($label)',
        fields: {'pid': proc.pid});
    return controller.stream;
  }

  /// Stop the capture cleanly. Idempotent — safe to call when no
  /// capture is active.
  Future<void> stop() async {
    await _activeSub?.cancel();
    _activeSub = null;
    await _subprocessStdoutSub?.cancel();
    _subprocessStdoutSub = null;
    final p = _subprocess;
    _subprocess = null;
    if (p != null) {
      try {
        p.kill(ProcessSignal.sigterm);
      } catch (e) {
        Log.instance.w('sysaudio', 'subprocess kill failed',
            fields: {'err': e.toString()});
      }
    }
    final c = _activeController;
    _activeController = null;
    if (c != null && !c.isClosed) {
      await c.close();
    }
    if (plat.isMacOS || plat.isAndroid) {
      try {
        await _control.invokeMethod<void>('stop');
      } catch (e) {
        Log.instance.d('sysaudio', 'native stop threw: $e');
      }
    }
    Log.instance.i('sysaudio', 'capture stopped');
  }

  bool get isCapturing => _activeController != null;
}

/// Singleton — survives navigation so a streaming transcription
/// keeps running across screen changes.
final systemAudioCaptureServiceProvider =
    Provider<SystemAudioCaptureService>(
        (ref) => SystemAudioCaptureService());
