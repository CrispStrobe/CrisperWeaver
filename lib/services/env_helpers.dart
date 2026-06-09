// Minimal libc setenv() FFI bridge for the handful of CrispASR env
// vars that gate compute-graph backend pinning. Dart's
// `Platform.environment` is read-only and reads from a cache taken
// at process start, so any var we want the native side to see must
// be installed via the actual libc `setenv()` call. Do that for the
// kokoro F0Ntrain / decoder-body Metal workaround at app boot —
// CrispASR reads these via `env_bool(...)` inside
// `kokoro_init_from_file`, so they have to be set BEFORE the first
// kokoro session opens.
//
// Apple platforms (macOS, iOS, iPadOS) only. The Metal regression
// doesn't affect Linux / Windows GPU paths (CUDA / Vulkan); pinning
// the stages there would just slow them down for no win.

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'log_service.dart';
import '../utils/platform_utils.dart' as plat;

/// Set `name=value` in the current process's environment via libc
/// `setenv(name, value, overwrite=1)`. Returns true on success.
///
/// No-op on every non-libc platform — Windows uses `_putenv_s` which
/// has a different signature; route through `Platform.environment`
/// (still read-only there, but the bug we're working around is
/// Apple-only, so we don't need Windows).
bool setEnv(String name, String value) {
  if (!(plat.isMacOS || plat.isIOS || plat.isLinux || plat.isAndroid)) {
    return false;
  }
  try {
    final libc = DynamicLibrary.process();
    final setenv = libc.lookupFunction<
        Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Int32),
        int Function(Pointer<Utf8>, Pointer<Utf8>, int)>('setenv');
    final namePtr = name.toNativeUtf8();
    final valuePtr = value.toNativeUtf8();
    try {
      final rc = setenv(namePtr, valuePtr, 1);
      if (rc != 0) {
        Log.instance
            .w('env', 'setenv returned non-zero', fields: {'name': name, 'rc': rc});
        return false;
      }
      Log.instance.d('env', 'set', fields: {'name': name, 'value': value});
      return true;
    } finally {
      calloc.free(namePtr);
      calloc.free(valuePtr);
    }
  } catch (e, st) {
    Log.instance.w('env', 'setenv failed', error: e, stack: st, fields: {'name': name});
    return false;
  }
}

/// Pin the kokoro F0Ntrain + decoder-body compute graphs to CPU on
/// Apple Silicon Metal. Workaround for the AdainResBlk1d divergence
/// localised by the upstream CrispASR bisect (2026-05-17). The text
/// encoder, BERT, predictor duration LSTM, and iSTFTNet generator
/// still run on Metal — only the two known-bad stages are pinned.
///
/// Drop this once upstream lands a real Metal fix for AdainResBlk1d
/// (see `handover-prompts/crispasr-kokoro-gpu-metal-regression.md`).
void applyKokoroMetalWorkaround() {
  // Apple platforms only — the bug is in ggml-metal, not in the
  // CUDA / Vulkan / CPU paths.
  if (!(plat.isMacOS || plat.isIOS)) return;
  setEnv('KOKORO_F0N_FORCE_CPU', '1');
  setEnv('KOKORO_DEC_FORCE_CPU', '1');
}

/// Point libespeak-ng at the bundled `espeak-ng-data/` so kokoro's
/// in-process phonemizer (`espeak_Initialize`) finds its data files
/// on platforms where the user's system doesn't have espeak-ng
/// pre-installed. Reads `CRISPASR_ESPEAK_DATA_PATH` inside CrispASR;
/// see `phonemize_espeak_lib` in src/kokoro.cpp.
///
/// Layouts per platform (relative to `Platform.resolvedExecutable`):
///   * macOS .app   — `../Resources/espeak-ng-data`
///   * Linux bundle — `lib/espeak-ng-data` (sibling to libwhisper.so)
///   * Windows bundle — `data/espeak-ng-data` or `espeak-ng-data` next to
///                      runner.exe
///   * Android — caller is expected to extract the assets dir to a
///               writable location first and pass [explicitOverride].
void applyKokoroEspeakDataPath({String? explicitOverride}) {
  String? candidate = explicitOverride;
  if (candidate == null) {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final List<String> candidates;
    if (plat.isMacOS) {
      // exeDir = .../crisper_weaver.app/Contents/MacOS
      candidates = ['$exeDir/../Resources/espeak-ng-data'];
    } else if (plat.isLinux) {
      candidates = ['$exeDir/lib/espeak-ng-data', '$exeDir/espeak-ng-data'];
    } else if (plat.isWindows) {
      candidates = ['$exeDir/data/espeak-ng-data', '$exeDir/espeak-ng-data'];
    } else {
      // iOS / Android — caller must provide the extracted-asset path.
      return;
    }
    for (final c in candidates) {
      if (Directory(c).existsSync()) {
        candidate = c;
        break;
      }
    }
  }
  if (candidate == null) {
    Log.instance.d('env',
        'bundled espeak-ng-data not found; kokoro will use system espeak-ng if available');
    return;
  }
  setEnv('CRISPASR_ESPEAK_DATA_PATH', candidate);
  Log.instance
      .i('env', 'pointed CRISPASR_ESPEAK_DATA_PATH at bundled data dir',
          fields: {'path': candidate});
}
