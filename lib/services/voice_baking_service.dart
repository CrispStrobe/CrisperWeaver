import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../main.dart' show modelServiceProvider;
import 'log_service.dart';
import 'model_service.dart';
import '../utils/platform_utils.dart' as plat;

/// Wraps `models/bake-chatterbox-voice-from-wav.py` from the sibling
/// CrispASR checkout. Spawns Python as a child process, streams stdout
/// + stderr into the in-app log buffer, and drops the resulting GGUF
/// next to the user's other voicepacks.
///
/// The script needs the upstream `chatterbox-tts` and `gguf` Python
/// packages installed (or available on `RESEMBLE_CHATTERBOX_SRC` for a
/// from-source clone). We don't try to install them — surface the
/// stderr verbatim instead so the user can `pip install` themselves.
///
/// Mobile (iOS / Android) has no Python runtime; this service throws
/// a clear "desktop-only" error there and the screen disables the
/// Bake button accordingly.
class VoiceBakingService {
  final ModelService modelService;
  VoiceBakingService(this.modelService);

  /// Whether voice baking is even attemptable on this platform.
  /// Mobile sandboxes ship no `python3` interpreter, so the screen
  /// hides itself there.
  static bool get isSupported =>
      plat.isMacOS || plat.isLinux || plat.isWindows;

  /// Best-effort sibling-checkout default — matches the CrisperWeaver
  /// build-script convention documented in README.md (CrispASR + the
  /// app cloned side-by-side under one parent dir).
  static const String defaultScriptPath =
      '../CrispASR/models/bake-chatterbox-voice-from-wav.py';

  /// Spawn the bake script with the given args, await completion,
  /// move the output into the models dir, and return the on-disk
  /// path. Logs every stdout / stderr line as it arrives so the
  /// in-app Log viewer reflects the bake's progress in real time.
  ///
  /// Throws [VoiceBakingException] on every failure mode (missing
  /// script, Python crashed, output GGUF wasn't produced). The
  /// message is user-readable so the screen can drop it straight
  /// into a SnackBar.
  Future<File> bake({
    required String wavPath,
    required String outputName,
    String pythonExecutable = 'python3',
    String scriptPath = defaultScriptPath,
    double exaggeration = 0.5,
    void Function(String line)? onStdout,
  }) async {
    if (!isSupported) {
      throw const VoiceBakingException(
          'Voice baking needs a desktop Python interpreter; '
          'mobile platforms have no Python runtime.');
    }
    final wav = File(wavPath);
    if (!await wav.exists()) {
      throw VoiceBakingException(
          'Reference WAV not found: $wavPath');
    }
    final script = File(scriptPath);
    if (!await script.exists()) {
      throw VoiceBakingException(
          'Bake script not found: $scriptPath. Adjust the path on the '
          'Bake voice screen if your CrispASR checkout lives elsewhere.');
    }

    await modelService.initialize();
    final modelsDir = modelService.whisperCppDir();
    await Directory(modelsDir).create(recursive: true);
    // Sandbox the Python output into the models dir so it shows up
    // in the picker without an extra copy step.
    final fileName =
        outputName.endsWith('.gguf') ? outputName : '$outputName.gguf';
    final outputPath = p.join(modelsDir, fileName);

    final args = [
      script.absolute.path,
      '--input',
      wav.absolute.path,
      '--output',
      outputPath,
      '--exaggeration',
      exaggeration.toStringAsFixed(2),
    ];
    Log.instance.i('voice-bake', 'spawn', fields: {
      'python': pythonExecutable,
      'script': script.absolute.path,
      'wav': wav.absolute.path,
      'out': outputPath,
      'exag': exaggeration,
    });

    final Process proc;
    try {
      proc = await Process.start(
        pythonExecutable,
        args,
        runInShell: false,
      );
    } catch (e) {
      throw VoiceBakingException(
          '$pythonExecutable not found on PATH or unable to launch ($e). '
          'Override the interpreter on the Bake voice screen if it lives '
          'in a venv.');
    }

    // Stream stdout + stderr into the log so the in-app Log viewer
    // shows progress live. Both go through utf8 line-decoders so a
    // 200-line bake doesn't ship as one big chunk at the end.
    final stdoutLines = <String>[];
    final stderrLines = <String>[];
    final stdoutDone = proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      Log.instance.d('voice-bake', line);
      stdoutLines.add(line);
      onStdout?.call(line);
    }).asFuture<void>();
    final stderrDone = proc.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      // The bake script prints progress to stderr too — log at info
      // so users see it in the default Log viewer level.
      Log.instance.i('voice-bake', line);
      stderrLines.add(line);
      onStdout?.call(line);
    }).asFuture<void>();

    final exitCode = await proc.exitCode;
    await stdoutDone;
    await stderrDone;

    if (exitCode != 0) {
      // Surface the last few stderr lines so the SnackBar message
      // explains what actually went wrong without dumping 200 lines.
      final tail = stderrLines.length <= 6
          ? stderrLines
          : stderrLines.sublist(stderrLines.length - 6);
      throw VoiceBakingException(
          'bake-chatterbox-voice-from-wav.py exited $exitCode: '
          '${tail.join("; ")}');
    }
    final out = File(outputPath);
    if (!await out.exists()) {
      throw const VoiceBakingException(
          'Bake script reported success but no GGUF was produced. '
          'Check the Logs screen for details.');
    }
    Log.instance.i('voice-bake', 'baked',
        fields: {'path': outputPath, 'bytes': await out.length()});
    return out;
  }
}

/// Thrown by [VoiceBakingService.bake] for every failure mode. The
/// message is user-readable so the screen can drop it straight into a
/// SnackBar.
class VoiceBakingException implements Exception {
  final String message;
  const VoiceBakingException(this.message);
  @override
  String toString() => 'VoiceBakingException: $message';
}

final voiceBakingServiceProvider = Provider<VoiceBakingService>(
    (ref) => VoiceBakingService(ref.watch(modelServiceProvider)));
