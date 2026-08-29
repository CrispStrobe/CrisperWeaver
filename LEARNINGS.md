# CrisperWeaver — Technical learnings

Things we spent hours figuring out while porting CrispASR's 10-backend FFI surface into a cross-platform Flutter app. Nothing here is news to someone who's shipped a native-code Flutter app before — everything here is something we'd have saved a day by knowing up front.

If a learning is still live (affects current work), it's linked from [`PLAN.md`](PLAN.md). If it's purely historical (a bug we fixed), it lives here.

---

## Dart FFI

### Generic helpers over `NativeFunction<T>` fail under `flutter test`, not `dart test`

**Symptom:** a helper like

```dart
R _tryLookup<T extends Function, R extends Function>(String sym) {
  return lib.lookupFunction<NativeFunction<T>, R>(sym);
}
```

compiles and runs under `dart test` but fails in `flutter test` with

> Expected type 'NativeFunction<T>' to be a valid and instantiated subtype of 'NativeType'

**Reason:** the Flutter test runner rewraps `NativeFunction<T>` generics differently from the standalone VM; `T` isn't visible as an instantiated type at the FFI lookup site.

**Fix:** drop the generic. Per-symbol `providesSymbol` probe + concrete `lookupFunction<Concrete, Concrete>`:

```dart
if (!lib.providesSymbol('crispasr_audio_load')) return null;
final fn = lib.lookupFunction<
    Int32 Function(Pointer<Utf8>, Pointer<Pointer<Float>>, Pointer<Int32>, Pointer<Int32>),
    int Function(Pointer<Utf8>, Pointer<Pointer<Float>>, Pointer<Int32>, Pointer<Int32>)
>('crispasr_audio_load');
```

More boilerplate, but it works everywhere.

### `calloc<Utf8>(n)` fails: Utf8 is not a `SizedNativeType`

**Symptom:** allocation lines like `calloc<Utf8>(16)` fail compilation on newer Dart FFI:

> 'Utf8' is not a 'SizedNativeType'

**Fix:** allocate as bytes, then cast:

```dart
final buf = calloc<Uint8>(16).cast<Utf8>();
```

### Optional FFI symbols: probe before bind

If your library may or may not expose a symbol (e.g. new helpers added in CrispASR 0.4.x), always `providesSymbol('foo')` before `lookupFunction`. Otherwise any older copy of the dylib crashes the app on startup.

### `CrispASR(modelPath)` loads the path as a *whisper* context — don't feed it auxiliary models

The `crispasr.CrispASR(modelPath)` constructor calls `whisper_init_from_file` on `modelPath`. Some instance methods (`vad`, `vadSlices`) take a *separate* `modelPath:` argument and never touch `_ctx` — so it's tempting to do `CrispASR(vadModel)` just to reach them. Don't: a VAD/LID/punc model loaded as a whisper context is a degenerate `_ctx`, and `dispose()` → `whisper_free()` over it **SIGABRTs the whole isolate**. (`VadService` did exactly this and was a silent no-op — §9.5.) Either open the context on a real ASR model and pass the aux model only as a method arg, or — better for VAD — call the *free* C function `crispasr_vad_slices` directly (no context). See `lib/native/vad_native.dart`.

### Verify which entrypoint actually works — the obvious one can fail silently

`crispasr_vad_segments` (the binding's `vad()`) uses whisper's *native* VAD loader and returns `-2` ("model init failed") for the Silero asset and the whisper-vad GGUF. The working call is the unified dispatcher `crispasr_vad_slices` (`vadSlices()`). When a binding exposes two similar entrypoints, check the C source's return codes against the model type you're actually passing before wiring a service to one — a swallowed `-2` looks identical to "no speech".

### A `dart run` CLI can't use the Flutter service layer

`bin/crisperweaver.dart` runs under plain `dart run`, which has no `WidgetsFlutterBinding`, `path_provider`, `rootBundle`, or Riverpod container — so the app's `services/` (which depend on all of those) are unreachable. Wrap `package:crispasr` (pure-Dart FFI) directly instead. The CLI therefore reaches *engine* capabilities at parity with the GUI, but not GUI orchestration (history, presets, cleanup); that split is documented in `docs/PARITY.md`.

## Dylib bundling

### `libcrispasr` is a compatibility alias, not a separate library

CrispASR's core dylib is still called `libwhisper.dylib` (historical — the project is a whisper.cpp fork). `libcrispasr.dylib` is a symlink (Unix) or copy (Windows) created by CMake post-build. Both point to the same file and export the same symbols; the Dart loader tries `libcrispasr` first, falls back to `libwhisper`.

**Don't** expect them to be independently versionable — they're the same code.

### On macOS, DT_NEEDED sibling dylibs must live in `Contents/Frameworks/`

The app bundles ten dylibs: `libwhisper.dylib` plus `libparakeet`, `libcanary`, `libcohere`, `libqwen3_asr`, `libgranite_speech`, `libcanary_ctc`, `libvoxtral`, `libvoxtral4b`, `libwav2vec2-ggml` — all linked as DT_NEEDED from libwhisper itself. `dyld` finds them via `@rpath/@loader_path` (CMake sets this correctly at build time), but they must physically sit next to `libwhisper.dylib` inside `Contents/Frameworks/`.

`scripts/bundle_macos_dylibs.sh` does the copy + ad-hoc codesign. Skipping the codesign causes Gatekeeper to refuse to load the auxiliary dylibs with a permissions error that looks like "library not found" — very misleading.

### On Linux, DT_NEEDED siblings go into `bundle/lib/` — plus version symlinks

Unlike macOS, Linux's `libwhisper.so` has a SONAME with a version number (e.g. `libwhisper.so.1`). The CMake build produces three files:

```
libwhisper.so -> libwhisper.so.1
libwhisper.so.1 -> libwhisper.so.1.8.4
libwhisper.so.1.8.4
```

The CI bundle script picks the real file (`.so.1.8.4`), copies it as `libwhisper.so`, then symlinks `libcrispasr.so → libwhisper.so`. Both open paths work. Missing sibling `.so`'s (parakeet/canary/...) are skipped with a warning — a slim build stays valid.

### Static libs linked into shared libs need `-fPIC`

**Symptom:** linking `libwav2vec2-ggml.a` (a CMake `STATIC` library) into `libwhisper.so` fails on Linux with

> relocation R_X86_64_32 against `.rodata' can not be used when making a shared object; recompile with -fPIC

**Fix:** `set_target_properties(wav2vec2-ggml PROPERTIES POSITION_INDEPENDENT_CODE ON)` in the CMakeLists for that target. macOS is lenient (always PIC); Linux enforces it.

## Flutter + macOS

### CardTheme / DialogTheme / TabBarTheme were renamed in 3.38

If you pinned Flutter ≤ 3.35 and bumped to 3.38.5, any custom theming like

```dart
cardTheme: CardTheme(elevation: 2)
```

stops compiling. The replacements are `CardThemeData`, `DialogThemeData`, `TabBarThemeData`. Same constructor args, just the `*Data` suffix.

### Abstract exception classes can't be thrown

`EngineException` was declared abstract (`abstract class EngineException implements Exception`). Calling `throw EngineException('...')` fails compilation. Either declare it concrete, or add a `GenericEngineException(this.message)` concrete subclass for the "no specific reason" cases. We did the latter.

### `RenderFlex overflowed by N pixels` on macOS initial window

On macOS the default NSWindow opens at a smaller-than-you-think size. If your top `Scaffold` has an AppBar + tabs + search field + status chip all in one row, you will overflow at 1024-wide. Iterative fixes we ended up with:

- `LayoutBuilder` with `constraints.maxWidth < 720` → wrap wide-form widgets in a narrow variant.
- Remove tab icons (just labels).
- `isDense: true` on the search field.
- Use `titleMedium` instead of `headlineSmall` in AppBar.
- Set `minSize` on the NSWindow in `MainFlutterWindow.swift`.
- Default window to 1200 × 800.

The Flutter inspector's "overflow by X pixels" message counts from the *outside in* — start with the top-level row and work inward. Don't bother with `Expanded` on the first pass; it usually isn't what you want.

### Xcode "Run Script" phase warning is noise

> Run script build phase 'Run Script' will be run during every build because it does not specify any outputs.

Flutter's own generated script phase. Cosmetic. Ignore.

## Flutter dependency pinning

### `material_color_utilities` is a constant moving target

Flutter SDK pins an exact version; ecosystem packages pin a broader range; the two occasionally disagree. Our override:

```yaml
dependency_overrides:
  material_color_utilities: ">=0.8.0 <0.12.0"
```

Revisit after every Flutter minor bump.

### `intl` version collision with `flutter_localizations`

Same issue. `flutter_localizations` pins `intl` tightly; packages like `share_plus` pin a range that doesn't overlap. Override:

```yaml
dependency_overrides:
  intl: ">=0.19.0 <0.21.0"
```

### `record_linux` 0.7.x breaks `record` 5.x's platform interface

`record 5.1.2` wants `record_linux ^1.3.0`, but pub's resolver picks `0.7.2` without an override. Symptom: Linux build fails because the mic-record plugin can't find `LinuxRecorder.registerWith()`. Override:

```yaml
dependency_overrides:
  record_linux: ^1.3.0
```

### `just_audio` has no native Windows / Linux implementation

Symptom (issue #1, Windows): `MissingPluginException(No implementation found for method disposeAllPlayers on channel com.ryanheise.just_audio.methods)` fires on the very first `AudioPlayer` constructor — so the app crashes before any UI renders. `just_audio`'s pubspec only declares `android` / `ios` / `macos` / `web` plugin platforms. The Flutter tool happily builds for Windows and Linux without warning, then the platform channel resolves to nothing at runtime.

Fix: route those two platforms through `just_audio_media_kit` (libmpv-backed). Initialise it before any player is constructed, but only on the affected platforms — calling it on macOS/iOS/Android is a no-op but cleaner to guard:

```yaml
dependencies:
  just_audio: ^0.10.5
  just_audio_media_kit: ^2.1.0
  media_kit_libs_windows_audio: any
  media_kit_libs_linux: any
```

```dart
// main.dart, before runApp()
if (Platform.isWindows || Platform.isLinux) {
  JustAudioMediaKit.ensureInitialized();
}
```

The Flutter generated plugin registrants pick up `media_kit_libs_windows_audio` automatically on the next `flutter build windows`. No manual edits to `windows/flutter/generated_plugin_registrant.cc`.

## CI patterns

### Sibling-repo checkout

CrisperWeaver's `pubspec.yaml` has `crispasr: { path: ../CrispASR/flutter/crispasr }`. CI's `checkout` actions therefore both live under `$GITHUB_WORKSPACE`:

```yaml
- uses: actions/checkout@v4
  with:
    path: repos/CrisperWeaver
- uses: actions/checkout@v4
  with:
    repository: CrispStrobe/CrispASR
    path: repos/CrispASR
```

`working-directory: repos/CrisperWeaver` on every subsequent step. The `../CrispASR/...` path resolves naturally.

Lesson: don't try to use a git submodule for this. Submodules pin a SHA; we want `main` both places. Sibling checkout is messier but gives you the "develop both repos in lockstep" workflow you actually wanted.

### `cancel-in-progress` is what you want

```yaml
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
```

When you push three commits in quick succession, only the last one runs to completion — the first two get cancelled mid-stream. Saves runner minutes and keeps CI status readable.

### `flutter analyze` infos/warnings ≠ errors

By default, `flutter analyze` exits non-zero on infos and warnings too. We only want to fail on errors:

```yaml
- run: |
    set +e
    flutter analyze --no-fatal-infos --no-fatal-warnings
    status=$?
    if [ $status -ne 0 ]; then
      echo "::error::flutter analyze reported errors"
      exit $status
    fi
```

### `cppcheck` hates third-party single-header libraries

`miniaudio.h` is 95K lines. cppcheck spends minutes on it and generates hundreds of warnings for code that isn't ours. Suppress by filename:

```yaml
--suppress="*:src/miniaudio.h" --suppress="*:*stb_vorbis.c"
```

## WAV parsing

### Signed 16-bit PCM: use `getInt16`, not `getUint16` then subtract

Classic off-by-one-bit mistake. Reading the sample as unsigned and subtracting 32768 to "re-center" gives you an output amplitude that's *almost* right but off by 1 LSB. Just use `byteData.getInt16(pos, Endian.little)` and divide by 32768 — floats handle the range directly.

### Chunk iteration: pad to 2 bytes

WAV chunks are padded to 2-byte boundaries. After reading a chunk, `if (chunkSize % 2 != 0) offset++;` — otherwise a fmt chunk with odd size (rare but legal) misaligns every subsequent chunk and you get "No data chunk found".

## macOS lifecycle + ggml teardown race

### Dispose heavy native state on `AppLifecycleListener.onExitRequested`

On the red-X close of a Flutter macOS app, the runtime calls `exit()` → `__cxa_finalize_ranges()`. Any global `std::vector<ggml_metal_device>` destructor that runs at that moment tries to free residency sets, but ggml-metal's background 500 ms keep-alive dispatch queue (`__ggml_metal_rsets_init_block_invoke`) is still alive → `ggml_metal_rsets_free` asserts → `abort` → macOS shows a "closed unexpectedly" dialog.

**Fix:** wire `AppLifecycleListener(onExitRequested: ...)` in the root Stateful widget. Inside it: dispose the engine (which tears down the whisper context, which cancels ggml-metal's dispatch queue), flush your log sink, *then* return `AppExitResponse.exit`. By the time `exit()` runs the global destructors, the Metal state is gone.

```dart
_lifecycle = AppLifecycleListener(onExitRequested: () async {
  ref.read(transcriptionServiceProvider).dispose();
  await Log.instance.enableFileSink(false);  // flush + close
  return AppExitResponse.exit;
});
```

`AppExitResponse` is in `dart:ui`, not `package:flutter/services.dart` as the name suggests — `import 'dart:ui' show AppExitResponse;`.

### Heavyweight Swift code in `MainFlutterWindow.swift` lingers forever

The standard Flutter-for-macOS template has a 26-line `MainFlutterWindow.swift`. Ours had 387 lines of dead `AudioProcessingPlugin` Swift (AVFoundation + Accelerate FFT via `DSPSplitComplex`). It was legacy from the method-channel audio path — replaced by CrispASR's FFI `crispasr_audio_load` long ago — but the Swift was still compiled, still registered the plugin, and still held `AVAudioEngine` references that contributed to the "closed unexpectedly" crash.

**Lesson:** when you rip out a method-channel-based feature on one platform, search for its *other* platform counterparts. I missed this on macOS after cleaning it from iOS. Grep for the plugin name across `ios/` AND `macos/`.

## Remote catalog naming drift

### Don't hardcode third-party file names — probe and build the catalog at runtime

We shipped a hardcoded catalog of `ModelDefinition` entries pointing at `huggingface.co/cstr/*-GGUF/resolve/main/*.gguf` URLs. Each entry was a guess based on the backend's HF-Space naming. Four of them were wrong — e.g. `cohere-transcribe-03-2026-q5_0.gguf` (our guess) vs `cohere-transcribe-q5_0.gguf` (actual). Users got `HTTP 404 "Entry not found"` with no way to recover.

**Fix:** add a `BackendRepo` struct with just `repoId` + `baseName`, and call `GET huggingface.co/api/models/<repo>?blobs=true` at runtime. Parse every `.gguf` sibling into a `ModelDefinition` with the **real** filename and **real** byte-size. Merge live-probed entries over the hardcoded defaults. Auto-probe on first model-manager open so users never have to know about a "refresh" button.

**Corollary:** at most, hardcode repo-level info (repo ID, display prefix), never file-level (filename, URL, size). HF file names drift when model authors republish.

## Model downloads

### `Dio.download()` overwrites the file — a `Range` header alone is not resume

**Symptom (issue #35):** every resumed model download failed its checksum, or reported `expected 745121600, got 674342336`, or — worse — passed verification and then failed to load. Retrying reproduced the identical broken file.

**Reason:** the request was right and the write was wrong. `ModelService` sent `Range: bytes=$existing-`, the server answered `206 Partial Content` with the tail, and `Dio.download()` opened its target with truncation and wrote that tail *over* the partial file. The result is short by exactly the bytes already on disk, and it is missing the **first** N bytes, not the last — which is why nothing about the file's tail looks wrong.

**Fix:** stream the response yourself and control the file mode (`DownloadEngine` in `lib/services/model_service.dart`):

```dart
// append only when the server confirmed *our* offset
final ok206 = status == 206 && contentRangeStart == existingBytes;
final sink = File(part).openWrite(
    mode: ok206 ? FileMode.append : FileMode.write);
```

Plus the three cases nobody writes on the first attempt: `200` means the server ignored the range → restart from zero; `416` on a full-length request means the file is already complete → stop, don't error; a `Content-Range` start that isn't the offset you asked for → restart, don't append.

**Lesson:** resume is a property of the *writer*, not of the request. Any HTTP helper whose job is "download a URL to a path" is entitled to truncate that path, and it will do so with a perfectly correct `206` in hand.

### A size "tolerance" masks truncation — verify against the server, not the catalogue

The same bug survived verification because the completeness check compared the file against `ModelDefinition.sizeBytes`, a hand-maintained *estimate*, and accepted anything within a tolerance. A shortfall smaller than the tolerance was declared fine, and the failure moved from the downloader (where the log says which URL and which byte range) to the engine loader hours later (where it says nothing useful at all).

**Fix:** verify against the length the transfer itself reported — `Content-Length` on a `200`, the total in `Content-Range` on a `206` — and require exact equality. Keep the catalogue size for what it is good for: a progress bar and a free-space estimate before the transfer starts.

**Corollary:** on a checksum failure, delete the partial before retrying. Leaving it means every retry resumes from the same poisoned offset and reproduces the same file, which reads to the user as a server-side problem.

## Logging infrastructure

### Disable Dio's `LogInterceptor` in apps that have their own log view

`package:dio`'s `LogInterceptor(requestHeader:true, responseHeader:true, responseBody:true)` emits ~50 trace lines per HTTP request (every header, every response body byte). We gated it on `kDebugMode` — which is true under `flutter run`, which is where users actually read in-app logs. Our own `download start` / `download done` + DioException summary in the catch already capture the signal. The interceptor was pure noise.

**Lesson:** log only at application-event granularity (download started, download failed with HTTP 404), not at network-protocol granularity. If you need network-protocol logs, gate them behind a separate "HTTP verbose" toggle, not a debug-mode flag.

### `stderr.writeln` on Windows GUI builds throws *async*, past your `try`/`catch`

Issue #1's log showed an `[uncaught] FileSystemException: writeFrom failed (errno=6)` for every log line on Windows, originating from `Log._emit → stderr.writeln`. The `_emit` site already had a sync `try { stderr.writeln(...) } catch (_) {}` around it. The error still escaped.

**Reason:** `IOSink.writeln` enqueues bytes synchronously and returns; the actual write happens later in the event loop via `_StdConsumer.addStream → _StdSink.writeln`. When stderr's underlying handle is invalid — exactly the case for a Windows GUI build detached from the console — the FileSystemException is raised in that later micro-task and bypasses the sync try/catch entirely. It lands on `platformDispatcher.onError` instead, surfacing as `[uncaught]` on every log line.

**Fix:** classify the stream once at startup with `stdioType(stderr)` and skip the write entirely when it returns `StdioType.other` (the value Dart uses for detached streams):

```dart
final bool _stderrUsable = stdioType(stderr) != StdioType.other;
// ...
if (kDebugMode) {
  debugPrint(formatted);
} else if (_stderrUsable) {
  try { stderr.writeln(formatted); } catch (_) {}
}
```

`stdioType` covers terminal, pipe, file, and other (the only category that actually fails). Wrapping `runZonedGuarded` around `main()` is the alternative, but it pushes complexity onto every other site in the app for one specific failure mode.

**Update (issue #35): `stdioType(stderr)` misdetects on the Windows GUI subsystem.** The fix above held for a while and then a Windows 11 release build produced the same `writeFrom failed, path = '' (OS Error: The handle is invalid, errno = 6)` on every log line — with `stdioType` reporting something *other* than `StdioType.other` over a handle that was dead anyway. The classification is a heuristic; a GUI-subsystem process inherits whatever the launcher left behind.

Two changes, and you want both:

1. **Require a terminal, don't merely exclude `other`** — on Windows release builds a double-clicked GUI process never has one, so `type == StdioType.terminal` is the honest test. Wrap the probe itself in `try`/`catch`: touching `stderr` can throw where stdio is unavailable.
2. **Disarm on the first observed failure.** Detection cannot be trusted, so treat the first failed console write as ground truth and stop mirroring for the rest of the process. `main()`'s `platformDispatcher.onError` recognises the failure (`FileSystemException` with an **empty** `path` — that is what separates it from a genuine file-write error) and clears the flag. Also attach a no-op handler to `stdout.done` / `stderr.done`: `IOSink.writeln` only queues bytes, and the failure of the deferred write is delivered on that future, where nobody is listening.

**Lesson:** when a platform probe is a heuristic, pair it with a disarm-on-failure path. One dead handle should cost you one log line, not one uncaught error per log line for the life of the process.

## Navigation — go_router

### `go()` to a path you are already under re-uses the page: `initState` never runs again

**Symptom (issue #35):** the voice-clone wizard collected a reference clip and called `context.go('/synthesize', extra: clip)`. The Synthesize screen read its hand-off in `initState`, so the clip was silently dropped and the clone then failed with a raw engine return code. It worked in every test that pushed the screen fresh.

**Reason:** the wizard is a child route of `/synthesize`. go_router keys a page by its path, so navigating from `/synthesize/clone` to `/synthesize` *re-uses the existing page instance* — Flutter updates the widget rather than creating a new element. `initState` ran once, when the screen was first opened, long before the clip existed.

**Fix:** `didUpdateWidget` is the hand-off hook, not `initState`:

```dart
@override
void didUpdateWidget(covariant SynthesizeScreen old) {
  super.didUpdateWidget(old);
  if (widget.handoff != null && widget.handoff != old.handoff) {
    _applyHandoff(widget.handoff!);
  }
}
```

We also seed the provider directly at the call site, so the state is correct even if the frame never rebuilds with new widget fields.

**Lesson:** any state a route receives as an argument needs an update path as well as an init path, on every router that identifies pages by location. The test that catches it navigates *from a child of the destination*, which is exactly the case a "push the screen and check it renders" widget test never exercises.

## Theming and dark mode

### Don't hardcode text colors — use `Theme.of(context).colorScheme.onSurface`

The Logs screen hardcoded `Colors.black87` as the default text colour for every log row. Black-on-dark-surface in dark mode → invisible text. Same mistake lurks wherever `Colors.black*` / `Colors.white*` is used without a theme-aware fallback. The fix is always `Theme.of(context).colorScheme.onSurface` (or `onPrimary` etc. for tinted backgrounds).

Legitimate uses of `Colors.white` still exist — specifically `foregroundColor: Colors.white` paired with `backgroundColor: Colors.red` on destructive-action buttons. Those are OK because both colors are explicit.

## Architecture decisions

### CoreML as an opt-in inside whisper.cpp, not a separate engine

Early scaffolding had a separate `EngineType.coreML` + iOS `CoreMLWhisperPlugin` that talked to a method channel. That's the wrong shape — whisper.cpp ships its own CoreML integration (`WHISPER_USE_COREML`) which loads a `.mlmodelc` for the encoder forward pass, uses the Apple Neural Engine, and falls back to the GGML encoder on error — all through the existing `whisper_full_*` API. Net effect: CoreML acceleration rides through the *same* `CrispASREngine` path with no engine-level fork.

Lesson: resist the urge to model every hardware accelerator as a separate engine. If the underlying library already has a "try accelerator X, fall back to CPU" path, expose it as a build-time flag, not a user-visible engine switch. You save the duplicated tokenizer / audio-loader / context-management code that each engine would otherwise need.

### Model format ≠ engine

`ModelType.whisperCpp` is a *file-format marker* (GGML / GGUF binary loadable by whisper/CrispASR context). It's NOT coupled to a hypothetical `WhisperCppEngine`. Same file lands in `CrispASREngine.loadModel()`. When renaming or culling engine types, grep carefully — the `whisperCpp` token has two unrelated meanings.

## Process / project hygiene

### Don't narrate a rename halfway

Renaming `susurrus-flutter` → `CrisperWeaver` across a Flutter project touches bundle IDs (macOS / iOS / Android), Kotlin package directories, Dart `package:` imports in tests, CI workflow paths, README prose, and a dozen `pubspec.yaml`-referenced identifiers. Mid-rename build attempts created empty shell directories at the intermediate path (`crisperweaver-flutter/`) that Xcode picked up as "stale file" warnings for weeks. Fix: rename atomically via a Python script, run `flutter clean`, then build. Don't `flutter build macos` between step 3 and 4 of the rename.

Corollary: grep the whole tree for the old name *before* declaring the rename done. It catches README references, doc URLs, and assert-messages you'd otherwise miss.

### AGPL-3.0 attribution via LicenseRegistry

Flutter's `showLicensePage` aggregates every pub dep's license. For *native* code bundled via dylib (CrispASR, whisper.cpp, ggml, miniaudio), pub doesn't know about them — register them manually at startup:

```dart
// lib/services/native_licenses.dart
LicenseRegistry.addLicense(() async* {
  yield LicenseEntryWithLineBreaks(
    ['CrispASR'],
    await rootBundle.loadString('assets/licenses/CrispASR.txt'),
  );
});
```

Keep the raw license text in `assets/licenses/` and declare the asset in `pubspec.yaml`. The *About* screen then shows the full list, satisfying AGPL's "provide the license with the conveyed work" requirement.

### Don't commit build artefacts

We accidentally committed `crispasr/target/` (Cargo build dir) and `Cargo.lock` from CrispASR during a CI fix. `.gitignore` additions + `git rm --cached` fixed it. Lesson: when fixing CI across a multi-repo tree, run `git status` frequently.

---

## VAD wire-up (v0.1.7, April 2026)

### Bundled GGUF asset + first-use extract is the cleanest pattern

The Silero VAD GGUF (~885 KB) ships as `assets/vad/silero-v6.2.0-ggml.bin` and `lib/services/vad_service.dart` exposes a single `ensureModel()` call that copies the rootBundle asset to `<appCache>/vad/silero-v6.2.0-ggml.bin` on first use. Whisper's `params.vad_model_path` / the session API's `transcribeVad(..., vadModelPath)` both take a concrete file path — they can't read Flutter asset URIs directly. The extract-to-cache step is a one-liner but it's *the* interop glue between Flutter and any FFI that wants a filesystem path. This pattern generalises: any future shared-library feature that wants a model path (pyannote GGUF for diarize, whisper-tiny for LID, canary-CTC for alignment) uses the same "bundle as asset → extract to cache → pass path" recipe.

### Engine dispatch sits at `CrispASREngine`, not the service layer

`TranscriptionService.transcribeFile` was the natural place to put "extract VAD model + pass to engine". Resist adding feature flags one layer higher. The service knows about files and jobs, the engine knows about FFI. `_performTranscription(vad, vadModelPath, ...)` forwards to `engine.transcribe(vad, vadModelPath)` unchanged — the service doesn't care which engine consumes the flag, and the engine dispatches whisper vs session internally. That separation kept v0.1.7 to ~10 lines of service-layer change for a feature spanning every backend.

### Whisper vs session-API are two different VAD paths

`CrispASREngine.transcribe()` branches on `_model != null` (whisper, direct `crispasr.CrispASR`) vs `_session != null` (everything else, via `CrispasrSession`):
- **Whisper path**: sets `TranscribeOptions.vad = true` + `vadModelPath = path`. whisper.cpp's internal `whisper_full_params.vad` does the slicing + internal 30 s seek. No stitching.
- **Session path**: calls `CrispasrSession.transcribeVad(pcm, vadModelPath)` — the C-ABI `crispasr_session_transcribe_vad` does VAD + merge/split + stitch with 0.1 s gaps + single transcribe + timestamp remap in one FFI hop.

Both paths take the same `vad: true` flag from the UI toggle. The fact that they dispatch differently internally is invisible to callers — that's what the DRY refactor bought us.

### Pinning to a sibling CrispASR checkout via `path:` dep

`pubspec.yaml` declares `crispasr: { path: ../CrispASR/flutter/crispasr }`. This means every commit here implicitly pins to whatever's in the sibling `main` branch at build time. For v0.1.7 we needed `CrispasrSession.transcribeVad` which landed in `package:crispasr` 0.4.3 (upstream CrispASR `main` @ `28e4f16`) — no pub.dev coordination, just push upstream first, then build downstream. The release-notes commit documents the exact upstream SHA so bisecting any issue can pin to a known-good pair.

### Watch for ancient tags that don't contain new work

Twice during this cycle we had tag divergence: `v0.4.3` was tagged on an older upstream commit that predated our VAD work. `git pull` silently put us at the old tag's HEAD, and the dylib we rebuilt was missing our changes. Fix: when switching CrispASR checkouts, always `git log --oneline main | head -5` and check the expected feature commit is there. `git tag --contains <commit>` is the right query for "which releases include my work".

---

## Upstream CrispASR v0.4.4–v0.4.8: what's now possible in-app

Every large piece of functionality the CrispASR CLI previously owned is reachable from Dart via `package:crispasr` 0.4.8:

| Capability | Dart surface | CrisperWeaver status |
|---|---|---|
| VAD + stitching | `CrispasrSession.transcribeVad()` | ✅ shipped v0.1.7 |
| Speaker diarization | `diarizeSegments(...)` | ⚠️ not yet — MFCC/k-means stopgap still in `diarization_service.dart` |
| Language ID | `detectLanguagePcm(...)` | ⚠️ not yet — UI currently assumes user sets language |
| CTC / forced alignment | `alignWords(...)` | ⚠️ not yet — word timestamps missing for qwen3/voxtral/granite/cohere |
| HF download | `cacheEnsureFile(...)` | ⚠️ not used — CrisperWeaver has its own Dio-based downloader |
| Model registry lookup | `registryLookup(...)` | ⚠️ not used — CrisperWeaver has its own model catalog |

The pattern is the same every time: the library call takes a PCM buffer + a model path, writes its answer into caller-allocated structs, and returns in one FFI hop. Wiring these is not engine work — it's service-layer plumbing matching the VAD wire-up from v0.1.7.

### App-sandbox cache vs `~/.cache/crispasr`

`cacheEnsureFile` / `cacheDir` from the lib write under `$HOME/.cache/crispasr` on POSIX. Works for desktop CrisperWeaver users who also use the CLI. Broken on iOS/Android where apps are sandboxed and `$HOME` points at the app container. For mobile, keep using the app's documents/caches dir (we already do via `path_provider`) and pass that as `cacheDirOverride` when we do start calling the lib's cache helper. Desktop users get the CLI-shared cache by default, mobile users get the sandboxed path — same symbol, different ambient configuration.

## Test-suite speed

### `tags:` on `group()` is not a flutter_test parameter

The dart test runner accepts `tags: [...]` on individual `test()` calls but not on `group()`. The naive group-level annotation:

```dart
group("slow stuff", () { ... }, tags: ["slow"]);  // analyzer error
```

fails with `The named parameter 'tags' isn't defined`. Apply tags per-test instead:

```dart
test("kokoro synth", tags: ["slow"], () { ... });
```

### `dart_test.yaml` `exclude_tags: slow` collides with CLI `--tags slow`

`flutter test --tags slow` after setting `exclude_tags: slow` in `dart_test.yaml` produces:

```
No tests match the requested tag selectors:
  include: "slow"
  exclude: "slow"
```

The intersection is empty. The CLI flag adds to include, doesn't clear the YAML exclude. Workaround: skip the YAML `exclude_tags` and rely on per-test `skip:` clauses (env-var-gated) to keep the default pass fast. Cost: tests with the slow tag still register and report as `Skip:` lines in default output, but they don't actually run.

### ggml-metal pipeline cache is per-process, not per-machine

ggml-metal compiles MSL pipelines lazily — every fresh process pays a 30-60 s "kernel JIT" cost per backend before the first decode step. The `pipelines` cache in `ggml_metal_device_t` is in-memory only; there's no env var to persist it, no `MTLBinaryArchive` integration in upstream. Two consequences:

1. **Running each test in its own `flutter test` invocation is the worst case.** Six backends × ~30 s JIT = ~3 min of pure overhead before any model decode happens. Bundling all opt-in roundtrips into a single `flutter test` invocation cut a 50 min serial sweep to ~25 min — even though each `CrispasrSession.open()` creates its own ggml_metal_device, Apple's system-level Metal driver caches compiled MSL within a process, so the second backend onward reuses pipelines for shared op shapes.
2. **CI runs are uncacheable today.** A persistent `MTLBinaryArchive` patch in `ggml/src/ggml-metal/ggml-metal-device.m` would write/read pipeline state objects to a per-device disk cache (`~/Library/Caches/ggml-metal/<device>.archive`), letting CI restore the cache between runs. ~half-day source patch; would cut sweep cost from ~25 min to ~5 min.

### `Hello world.` is too long for "is this dispatch arm wired" tests

A TTS model generates roughly one second of audio per 2-3 input words. "Hello world." → ~1.5 s of decode loop. "Hi." → ~0.5 s. For a "did the dispatch arm route correctly" test, neither produces interesting audio — but the shorter input saves 1 s × per-token-decode-cost across every TTS test in the suite. We use "Hi." across all four TTS roundtrips.

### 2 s ASR clip vs full sentence

`test/jfk-2s.wav` is the first 2 s of `test/jfk.wav` (`ffmpeg -t 2`). The full clip is 11 s of "And so my fellow americans, ask not what your country can do for you. Ask what you can do for your country." The 2 s trim only covers "And so my fellow americans" — `expect(transcript, contains("ask"))` fails because "ask" is in the back half. We assert `contains("americans")` instead, which is in both. ~5× faster ASR decode for the same dispatch verification.

---

## Flutter Web / PWA

### `dart:io` Platform causes white screen on web

`dart:io` compiles for web (dart2js stubs it) but `Platform.isWindows`, `Platform.operatingSystem`, etc. throw `UnsupportedError` at **runtime**. If any `Platform.*` call executes before `runApp()`, the app dies silently — white screen with no visible error (only in DevTools console). We had 47 files importing `dart:io` for Platform checks.

Fix: created `lib/utils/platform_utils.dart` with web-safe wrappers (`isWeb`, `isAndroid`, `isMacOS`, etc.) that return `false` on web instead of throwing. Replaced all 50+ `Platform.*` call sites across 23 files. Top-level initializers like `final bool _stderrUsable = stdioType(stderr)` are especially dangerous — they run at import time, not at call time.

### `file_picker` returns bytes on web, not paths

On native platforms, `FilePicker.pickFiles()` returns `PlatformFile.path` (a filesystem string). On web, `path` is always `null` — only `PlatformFile.bytes` (`Uint8List`) is available. The entire transcription pipeline (`transcribeFile(File(...))`) assumed filesystem paths.

Fix: added `fileBytes` / `fileNames` fields to `RobustFilePick`, a `transcribeBytes()` method on `TranscriptionService`, and a web-specific branch in the transcription screen that sends raw bytes to `HfSpaceEngine.transcribeBytes()` which POSTs them directly to the HF Space API.

### Vercel token types: `vca_*` vs `vcp_*`

`npx vercel login` stores an OAuth session token (`vca_*`) in `~/.local/share/com.vercel.cli/auth.json`. This works for local CLI commands but **fails** in CI with "The token provided via --token argument is not valid." CI needs a proper API token (`vcp_*`) created at vercel.com/account/tokens. The `~/.env` file has the correct `vcp_*` token.

### CrispEmbed WASM: Emscripten `-pthread` must be in compile flags, not just link flags

When compiling CrispEmbed to WASM, passing `-pthread` only in `CMAKE_EXE_LINKER_FLAGS` is insufficient. Object files compiled without `-pthread` lack atomics/bulk-memory features, causing `wasm-ld: error: --shared-memory is disallowed by X.o because it was not compiled with 'atomics' or 'bulk-memory' features`. Fix: add `-pthread` to both `CMAKE_C_FLAGS` and `CMAKE_CXX_FLAGS`.

### COOP/COEP headers required for SharedArrayBuffer

WASM pthreads require `SharedArrayBuffer`, which browsers only enable under cross-origin isolation. The `vercel.json` must set `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp` headers. Without these, the WASM module falls back to single-threaded mode. HuggingFace model file downloads work under COEP because HF sets `Cross-Origin-Resource-Policy: cross-origin` on file responses.

### HF Space free-tier Docker build timeout is ~5 minutes

The HF free-tier Docker build has a hard timeout around 5–6 minutes. Compiling CrispASR from source (60+ C++ backends) takes 15+ minutes even with `-j1`. Solution: upload pre-built binaries to GitHub Releases and `curl` them in the Dockerfile instead of compiling. Changed from multi-stage build to single-stage with pre-built tarball.

### Ubuntu 24.04 in Docker: UID 1000 conflict and pip

Ubuntu 24.04 base images have a pre-existing `ubuntu` user with UID 1000. `useradd -u 1000 app` fails silently. Use `USER 1000` (numeric) instead of `USER app`. Also, pip requires `--break-system-packages` on 24.04 (PEP 668).

### HF Space free-tier: 3 cpu-basic slots max

The free tier allows 3 concurrent `cpu-basic` Spaces. Starting a 4th gives "Quota exceeded for flavor cpu-basic". Pause unused Spaces via `HfApi().pause_space('cstr/name')` to free slots.

### Kokoro g2p dict auto-download needs writable HOME

The `phonemizer.cpp` g2p dict auto-download writes to `$HOME/.cache/crispasr/`. In Docker containers running as non-root, `HOME` may point to a non-writable directory. Set `ENV HOME=/cache` (or another writable path) in the Dockerfile. Pre-downloading dicts at build time is more reliable than runtime auto-download.

### Shared library SOVERSION symlinks in tarballs

When packaging shared libraries (e.g. `libcrispasr.so.0.7.1`), the tarball must include SOVERSION symlinks (`libcrispasr.so.1 → libcrispasr.so.0.7.1`) because the binary links against the SOVERSION name, not the full version. Missing symlinks cause silent `dlopen` failures — the binary starts but can't find its libraries.

---

## Codebase optimization (June 2026)

### File size thresholds for splitting

**Symptom:** `model_service.dart` at 5696 lines mixed static catalog data (~4300 lines of `const` model definitions + language lists) with operational logic (download, verify, probe). Navigation was painful, IDE indexing slow, and review diffs enormous even for small logic changes.

**Fix:** Extract all static data + data classes into `model_catalog.dart` via an `abstract final class ModelCatalog` (non-instantiable container). The service re-exports it (`export 'model_catalog.dart'`) so all existing `import 'model_service.dart'` sites continue to work without changes.

**Rule of thumb:** when a file exceeds ~2000 lines, check whether it mixes data definitions with behavior. Data (enums, const maps, value classes) extracts cleanly; behavior (methods with side effects, I/O, state) usually can't be split without changing the API.

### HTTP client consolidation isn't always worth it

**Symptom:** the app depends on both `dio` (downloads with progress/resume) and `http` (simple JSON POST for LLM cleanup/summarize).

**Decision:** deferred. The 3 `http` call sites have 20+ `MockClient`-based tests that would all need rewriting for `dio`'s `HttpClientAdapter` mock pattern. The dependency overlap is small (both are transitive deps of other packages anyway), and the test churn risk outweighs the binary-size savings.

### optipng -o2 is the sweet spot for CI-friendly PNG compression

`-o7` on a 1 MB PNG takes 5+ minutes; `-o2` takes seconds and captures ~90% of the savings (37% reduction on 1024×1024 RGBA). Uncompressed PNGs from design tools often have inefficient IDAT encoding that lossless recompression fixes trivially.

