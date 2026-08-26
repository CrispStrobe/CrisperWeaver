// MemoryEstimator — §5.23 Q2 v2 OOM pre-flight guard.
//
// Estimates whether the user can afford `N` concurrent
// transcription workers without running out of RAM. Used by the
// batch drain loop to clamp the user-requested session count down
// to what actually fits before any worker isolates spawn.
//
// Two readings:
//   • [physicalMemoryBytes] — total system RAM. Cheap, cached at
//     first call. We use this as the conservative ceiling on
//     desktop (where actual "available" memory is hard to measure
//     portably across macOS/Linux/Windows) and as the only reading
//     on mobile (where we can't shell out at all).
//   • [estimateModelBytes] — model file size on disk. We treat the
//     in-memory cost as ~1.6× the on-disk size: ggml quantised
//     weights expand slightly + KV cache + activations. Empirical
//     across whisper / parakeet / canary / voxtral on M1.
//
// What we DON'T do:
//   - Live RSS introspection (`ProcessInfo` would need a per-
//     platform channel; the overhead isn't worth it for a coarse
//     pre-flight).
//   - macOS `vm_stat` parsing for "free pages" (changes by the
//     second; misleading on systems with lots of inactive cache).
//
// Conservative-by-design: we err on the side of refusing one
// extra worker rather than letting the user OOM mid-batch.
//
// Cross-platform: ONE platform-specific call —
// `ProcessInfo.processInfo.physicalMemory` is exposed by
// `Platform.numberOfProcessors`'s sibling on most OSes via
// `dart:io`'s `sysInfo`-style helpers. We hand-roll the read
// below; falls back to a per-platform constant if the read
// throws.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/platform_utils.dart' as plat;
import 'log_service.dart';

class MemoryEstimate {
  const MemoryEstimate({
    required this.physicalMemoryBytes,
    required this.modelBytesPerWorker,
    required this.requestedWorkers,
    required this.affordableWorkers,
    required this.projectedUsageBytes,
    required this.reason,
  });

  /// Total system RAM the host advertises.
  final int physicalMemoryBytes;

  /// What we expect ONE worker to occupy in RAM. Caller-supplied
  /// (typically derived from `File.lengthSync()` × overhead).
  final int modelBytesPerWorker;

  /// What the user asked for (slider value).
  final int requestedWorkers;

  /// What we'll actually spin up — clamped so projected usage
  /// stays under [memoryHeadroomFraction] of physicalMemoryBytes.
  /// Always >= 1.
  final int affordableWorkers;

  /// projection = baseRssEstimate + modelBytes × affordableWorkers.
  final int projectedUsageBytes;

  /// Human-readable explanation for the UI + log. One of:
  ///   - "fits": requested == affordable
  ///   - "clamped": affordable < requested (memory-bound)
  ///   - "unknown-mem": couldn't read physicalMemory; serial-only
  final String reason;

  bool get wasClamped => affordableWorkers < requestedWorkers;

  String get prettyProjected =>
      '${(projectedUsageBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  String get prettyPhysical =>
      '${(physicalMemoryBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  String get prettyPerWorker =>
      '${(modelBytesPerWorker / (1024 * 1024)).round()} MB';
}

class MemoryEstimator {
  MemoryEstimator();

  /// Multiplier from on-disk model size → expected in-memory cost.
  /// 1.6× is a conservative average across the backends we support
  /// on M1 (whisper ~1.4×, voxtral ~1.7×, parakeet ~1.3×). Tuned to
  /// favour underutilizing memory over OOM-ing.
  static const double modelOverheadMultiplier = 1.6;

  /// Fraction of physicalMemory we're willing to project the
  /// worker pool to occupy. 0.5 leaves half the box for the OS,
  /// other apps, our own audio decoder, the GPU's memory shadow,
  /// + browser tabs the user has open. Lower than this and we
  /// rarely allow N > 1 on a 16 GB laptop; higher and we risk
  /// thrashing.
  static const double memoryHeadroomFraction = 0.5;

  /// Rough "everything else CrisperWeaver needs" estimate. Used as
  /// the floor of the projection so a 1-worker pool of a 100 MB
  /// model doesn't claim it can run 50 workers.
  static const int baseRssBytes = 400 * 1024 * 1024; // 400 MB

  /// Everything that scales with the LENGTH of the audio, per second.
  ///
  /// Measured 2026-08-26, qwen3-asr-0.6b-q4_k (631 MB GGUF) on macOS/Metal,
  /// 16 GB, via the CrispASR CLI — the same unchunked `crispasr_c_api`
  /// session path the app takes. Peak RSS went 1.415 GB at 11 s of audio to
  /// 1.576 GB at 1804 s, a slope of ~90 KB per audio-second, of which 64 KB
  /// is the f32 PCM itself (16 kHz × 4 bytes) and the rest is encoder output
  /// plus KV growth.
  ///
  /// We budget 256 KB/s rather than the measured 90 KB/s because the app
  /// holds more copies of the PCM than the CLI does: the decoded buffer, the
  /// copy handed across the worker-isolate boundary, and the native side's
  /// own. Deliberately conservative — the cost of over-estimating is a
  /// refusal the user can override, and the cost of under-estimating is a
  /// frozen machine.
  static const int bytesPerAudioSecond = 256 * 1024;

  /// Ceiling for a SINGLE transcription, as a fraction of system RAM. More
  /// permissive than [memoryHeadroomFraction] (which sizes a whole pool of
  /// concurrent workers) because one foreground decode is the thing the user
  /// explicitly asked for — we only refuse what cannot plausibly succeed.
  static const double transcribeHeadroomFraction = 0.8;

  int? _cachedPhysical;
  bool _haveReadPhysical = false;

  /// System RAM in bytes, cached. Returns null when the host
  /// refuses to report (very rare; treat as "unknown, fall back to
  /// serial"). The first call shells out / reads `/proc/meminfo` /
  /// hits `sysctl`; every subsequent call returns the cached value
  /// (including the cached-null case so we don't retry a broken
  /// platform probe).
  int? physicalMemoryBytes() {
    if (_haveReadPhysical) return _cachedPhysical;
    try {
      _cachedPhysical = _readPhysicalMemory();
    } catch (e) {
      Log.instance.w('memory-est', 'physical memory probe failed',
          fields: {'err': e.toString()});
      _cachedPhysical = null;
    }
    _haveReadPhysical = true;
    return _cachedPhysical;
  }

  /// Platform-specific reader for total RAM.
  int? _readPhysicalMemory() {
    if (plat.isMacOS) {
      // `sysctl -n hw.memsize` returns total bytes, no parsing
      // needed. Cheap, blocks <1 ms.
      final r = Process.runSync('sysctl', ['-n', 'hw.memsize']);
      if (r.exitCode != 0) return null;
      return int.tryParse(r.stdout.toString().trim());
    }
    if (plat.isLinux) {
      // /proc/meminfo's first line: `MemTotal:   16384444 kB`.
      final raw = File('/proc/meminfo').readAsStringSync();
      final line =
          raw.split('\n').firstWhere((l) => l.startsWith('MemTotal:'),
              orElse: () => '');
      if (line.isEmpty) return null;
      final parts = line.split(RegExp(r'\s+'));
      final kb = int.tryParse(parts[1]);
      if (kb == null) return null;
      return kb * 1024;
    }
    if (plat.isWindows) {
      // wmic is slow (~500 ms) but ubiquitous. Result row:
      //   "TotalVisibleMemorySize="
      //   "16384444"
      // We just look for the integer.
      final r = Process.runSync(
        'wmic',
        ['OS', 'get', 'TotalVisibleMemorySize', '/value'],
        runInShell: true,
      );
      if (r.exitCode != 0) return null;
      final m =
          RegExp(r'TotalVisibleMemorySize=(\d+)').firstMatch(r.stdout.toString());
      if (m == null) return null;
      final kb = int.tryParse(m.group(1)!);
      if (kb == null) return null;
      return kb * 1024;
    }
    // iOS / Android: shelling out isn't allowed inside the
    // sandbox. Use a conservative platform default. Newer iPhones
    // ship with 6-8 GB; older with 3-4 GB; we pick a lower-middle
    // estimate so the pre-flight refuses too-aggressive slider
    // settings on the cheapest device the app might run on.
    if (plat.isIOS) return 3 * 1024 * 1024 * 1024; // 3 GB
    if (plat.isAndroid) return 4 * 1024 * 1024 * 1024; // 4 GB
    return null;
  }

  /// File-size probe for the model GGUF on disk. Returns 0 when
  /// the path doesn't exist (caller treats that as "unknown, refuse
  /// to start workers"). Wraps a synchronous stat — sub-millisecond
  /// on any platform.
  static int modelFileSizeBytes(String? modelPath) {
    if (modelPath == null || modelPath.isEmpty) return 0;
    try {
      final f = File(modelPath);
      if (!f.existsSync()) return 0;
      return f.lengthSync();
    } catch (e) {
      Log.instance.w('memory-est', 'model file size probe failed',
          fields: {'path': modelPath, 'err': e.toString()});
      return 0;
    }
  }

  /// Compute the projection for `requested` workers against
  /// `modelPath`. Returns a MemoryEstimate covering both the
  /// requested-vs-affordable answer and the prettified strings
  /// the Settings UI can display.
  MemoryEstimate estimate({
    required int requested,
    required String? modelPath,
  }) {
    final phys = physicalMemoryBytes();
    final modelBytes = (modelFileSizeBytes(modelPath) *
            modelOverheadMultiplier)
        .round();
    if (phys == null || modelBytes <= 0) {
      // Couldn't read physical memory OR couldn't find the model.
      // Refuse all parallel sessions — caller falls back to the
      // serial path. Set affordableWorkers = 1 so the math elsewhere
      // doesn't divide by zero.
      return MemoryEstimate(
        physicalMemoryBytes: phys ?? 0,
        modelBytesPerWorker: modelBytes,
        requestedWorkers: requested,
        affordableWorkers: 1,
        projectedUsageBytes: baseRssBytes,
        reason: 'unknown-mem',
      );
    }
    final budget = (phys * memoryHeadroomFraction).round() - baseRssBytes;
    // How many workers fit inside `budget`?
    final canFit = modelBytes <= 0 ? requested : budget ~/ modelBytes;
    final affordable =
        canFit < 1 ? 1 : (canFit > requested ? requested : canFit);
    final projected = baseRssBytes + modelBytes * affordable;
    final reason = affordable < requested ? 'clamped' : 'fits';
    return MemoryEstimate(
      physicalMemoryBytes: phys,
      modelBytesPerWorker: modelBytes,
      requestedWorkers: requested,
      affordableWorkers: affordable,
      projectedUsageBytes: projected,
      reason: reason,
    );
  }

  /// Test-only injection point so unit tests can pin a physical
  /// memory value without shelling out. Also marks the cache as
  /// "already read" so `physicalMemoryBytes()` returns the injected
  /// value even if it's null (covers the "what if the platform
  /// refuses to report" path).
  @visibleForTesting
  // ignore: avoid_setters_without_getters
  set physicalMemoryBytesForTest(int? value) {
    _cachedPhysical = value;
    _haveReadPhysical = true;
  }
}

/// Singleton — the estimator caches the physicalMemory read on
/// first call, so reuse across the settings screen + drain loop
/// avoids a second shell-out.
final memoryEstimatorProvider =
    Provider<MemoryEstimator>((ref) => MemoryEstimator());

/// Verdict from [MemoryEstimator.estimateTranscribe] — the pre-flight for a
/// SINGLE transcription, as opposed to [MemoryEstimate] which sizes a worker
/// *pool*.
///
/// The pool estimate only ever asked "how many copies of this model fit".
/// That misses the failure the field reports actually hit (#33, #34): one
/// worker, one model, but an audio file long enough that the decoder's own
/// buffers dwarf the weights. A whole-OS freeze on a CPU-only Windows build
/// is what memory exhaustion looks like from the outside — the box starts
/// thrashing the pagefile and the UI stops repainting, so there is no crash
/// log to read afterwards.
class TranscribeMemoryEstimate {
  const TranscribeMemoryEstimate({
    required this.fits,
    required this.physicalMemoryBytes,
    required this.modelBytes,
    required this.audioBytes,
    required this.projectedUsageBytes,
    required this.audioSeconds,
    required this.reason,
  });

  /// False when the projection exceeds the budget. Callers should refuse
  /// rather than start the decode.
  final bool fits;
  final int physicalMemoryBytes;

  /// Weights, already multiplied by [MemoryEstimator.modelOverheadMultiplier].
  final int modelBytes;

  /// Everything that scales with audio length — see
  /// [MemoryEstimator.bytesPerAudioSecond].
  final int audioBytes;
  final int projectedUsageBytes;
  final double audioSeconds;

  /// One of `fits`, `too-large`, `unknown-mem` (host refused to report RAM,
  /// or the model file could not be stat'ed — we do not block on a guess).
  final String reason;

  String get prettyProjected =>
      '${(projectedUsageBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  String get prettyPhysical =>
      '${(physicalMemoryBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  String get prettyAudio {
    final m = audioSeconds ~/ 60;
    final s = (audioSeconds % 60).round();
    return m > 0 ? '${m}m ${s}s' : '${s}s';
  }
}

/// Pre-flight guard for one transcription. Kept as an extension so the
/// pool-sizing class above stays exactly as it was.
extension TranscribePreflight on MemoryEstimator {
  /// Projected footprint of transcribing [audioSeconds] of audio with the
  /// model at [modelPath].
  ///
  /// `projected = baseRss + modelBytes×1.6 + audioSeconds×bytesPerAudioSecond`
  ///
  /// Refuses when that exceeds [transcribeHeadroomFraction] of system RAM.
  /// The fraction is more permissive than the pool's 0.5 on purpose: a single
  /// foreground transcription is what the user actually asked for, so we only
  /// stand in the way when it cannot plausibly succeed.
  ///
  /// This is a FLOOR, not a bound. The linear term is calibrated against
  /// LLM-style backends on a GPU path (see [bytesPerAudioSecond]); backends
  /// that materialise a dense N×N attention mask grow superlinearly in audio
  /// length, and on a CPU-only build there is no flash-attention path to save
  /// them. So `fits == true` means "not obviously impossible", never
  /// "guaranteed".
  TranscribeMemoryEstimate estimateTranscribe({
    required String? modelPath,
    required double audioSeconds,
  }) {
    final phys = physicalMemoryBytes();
    final modelBytes =
        (MemoryEstimator.modelFileSizeBytes(modelPath) *
                MemoryEstimator.modelOverheadMultiplier)
            .round();
    final audioBytes =
        (audioSeconds * MemoryEstimator.bytesPerAudioSecond).round();
    if (phys == null || phys <= 0 || modelBytes <= 0) {
      // Never block on a guess. An unreadable model path is a different
      // failure and the load below will report it properly.
      return TranscribeMemoryEstimate(
        fits: true,
        physicalMemoryBytes: phys ?? 0,
        modelBytes: modelBytes,
        audioBytes: audioBytes,
        projectedUsageBytes: MemoryEstimator.baseRssBytes + audioBytes,
        audioSeconds: audioSeconds,
        reason: 'unknown-mem',
      );
    }
    final projected =
        MemoryEstimator.baseRssBytes + modelBytes + audioBytes;
    final budget =
        (phys * MemoryEstimator.transcribeHeadroomFraction).round();
    final fits = projected <= budget;
    return TranscribeMemoryEstimate(
      fits: fits,
      physicalMemoryBytes: phys,
      modelBytes: modelBytes,
      audioBytes: audioBytes,
      projectedUsageBytes: projected,
      audioSeconds: audioSeconds,
      reason: fits ? 'fits' : 'too-large',
    );
  }
}
