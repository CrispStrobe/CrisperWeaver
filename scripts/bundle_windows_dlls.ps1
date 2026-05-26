# scripts/bundle_windows_dlls.ps1
#
# Copy every CrispASR DLL next to the Flutter Windows runner's exe so
# `DynamicLibrary.open()` in the Dart FFI binding finds them on app
# start-up.
#
# Env:
#   CRISPASR_DIR          path to the CrispASR checkout
#                         (default: ..\CrispASR)
#   CRISPASR_BUILD_SUBDIR cmake binary dir under CRISPASR_DIR
#                         (default: build — but build_windows.ps1
#                         passes "build-flutter-bundle" to match the
#                         macOS flow)
#   RUNNER_DIR            path to the runner output directory
#                         (default: build\windows\x64\runner\Release)
#
# Usage: pwsh -File scripts\bundle_windows_dlls.ps1
#
# Normally invoked by scripts\build_windows.ps1 — call it directly only
# if you've already produced whisper.dll and the flutter runner.

$ErrorActionPreference = "Stop"

$crispasrDir         = if ($env:CRISPASR_DIR)          { $env:CRISPASR_DIR }          else { "..\CrispASR" }
$crispasrBuildSubdir = if ($env:CRISPASR_BUILD_SUBDIR) { $env:CRISPASR_BUILD_SUBDIR } else { "build" }
$runnerDir           = if ($env:RUNNER_DIR)            { $env:RUNNER_DIR }            else { "build\windows\x64\runner\Release" }
$cBase               = Join-Path $crispasrDir $crispasrBuildSubdir

if (-not (Test-Path $runnerDir)) {
    throw "Runner dir not found: $runnerDir. Run flutter build windows --release first."
}
if (-not (Test-Path $cBase)) {
    throw "CrispASR build tree not found: $cBase. Build CrispASR first or override CRISPASR_BUILD_SUBDIR."
}

# Helper: probe each known per-config output layout MSVC may produce.
function Find-Dll($baseDir, $name) {
    $candidates = @(
        "$baseDir\bin\Release\$name.dll",
        "$baseDir\src\Release\$name.dll",
        "$baseDir\Release\$name.dll",
        "$baseDir\bin\$name.dll",
        "$baseDir\src\$name.dll",
        "$baseDir\$name.dll"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }
    return $null
}

# Core library — whisper.dll. Required.
$whisperDll = Find-Dll $cBase "whisper"
if (-not $whisperDll) {
    throw "whisper.dll not found under $cBase. Run scripts\build_windows.ps1 (or `cmake --build $crispasrBuildSubdir --config Release --target crispasr`) first."
}

Write-Host "Bundling from: $whisperDll"
Copy-Item $whisperDll "$runnerDir\whisper.dll" -Force
# crispasr.dll alias — Dart FFI loader probes this name first.
Copy-Item $whisperDll "$runnerDir\crispasr.dll" -Force

# Sibling backend DLLs — DT_NEEDED via the import table. If whisper.dll
# was linked with these as PUBLIC dependencies, the DLLs must sit
# alongside it or LoadLibrary fails. List mirrors the BACKEND_TARGETS
# in scripts/build_macos.sh so TTS + post-processors are covered too.
$siblings = @(
    "parakeet", "canary", "canary_ctc", "qwen3_asr", "cohere",
    "granite_speech", "granite_nle", "voxtral", "voxtral4b",
    "wav2vec2-ggml", "glm-asr", "kyutai-stt", "firered-asr",
    "firered-vad", "marblenet-vad", "firered-lid", "omniasr",
    "vibevoice", "ecapa-lid", "moonshine", "moonshine_streaming",
    "gemma4_e2b", "mimo_tokenizer", "mimo_asr", "qwen3_tts", "orpheus",
    "kokoro", "pyannote-seg", "silero-lid", "fireredpunc"
)
foreach ($name in $siblings) {
    $dll = Find-Dll $cBase $name
    if ($dll) {
        Copy-Item $dll "$runnerDir\$name.dll" -Force
        Write-Host "  bundled $name.dll"
    } else {
        Write-Host "  skip:  $name.dll (built as STATIC archive — already in whisper.dll)" -ForegroundColor DarkGray
    }
}

# ggml runtime (new-style CrispASR builds ship it as separate DLLs).
foreach ($g in @("ggml", "ggml-cpu", "ggml-base", "ggml-blas")) {
    $dll = Find-Dll $cBase $g
    if ($dll) {
        Copy-Item $dll "$runnerDir\$g.dll" -Force
        Write-Host "  bundled $g.dll"
    }
}

# espeak-ng runtime — kokoro NEEDS libespeak-ng.dll at load time
# (linked at build via CRISPASR_HAVE_ESPEAK_NG). Without this DLL +
# espeak-ng-data\ next to runner.exe, kokoro_synthesize returns no
# PCM and the user sees "synth failed : Exception: synthesize
# returned no audio for backend kokoro" — that's issue #6.
#
# ESPEAK_NG_ROOT is exported by the CI workflow's source build of
# espeak-ng. Layout matches `cmake --install` so files live under
# bin\, lib\, share\espeak-ng-data\.
$espeakRoot = $env:ESPEAK_NG_ROOT
if ($espeakRoot -and (Test-Path $espeakRoot)) {
    # DLL: cmake install lays it under bin\ on Windows.
    $espeakDll = $null
    foreach ($cand in @("$espeakRoot\bin\libespeak-ng.dll", "$espeakRoot\libespeak-ng.dll")) {
        if (Test-Path $cand) { $espeakDll = $cand; break }
    }
    if ($espeakDll) {
        Copy-Item $espeakDll "$runnerDir\libespeak-ng.dll" -Force
        Write-Host "  bundled libespeak-ng.dll from $espeakDll"
    } else {
        Write-Host "::error::libespeak-ng.dll not found under $espeakRoot" -ForegroundColor Red
        # Don't exit — desktop still works for non-kokoro backends.
    }
    $espeakExe = $null
    foreach ($cand in @("$espeakRoot\bin\espeak-ng.exe", "$espeakRoot\espeak-ng.exe")) {
        if (Test-Path $cand) { $espeakExe = $cand; break }
    }
    if ($espeakExe) {
        Copy-Item $espeakExe "$runnerDir\espeak-ng.exe" -Force
        Write-Host "  bundled espeak-ng.exe from $espeakExe"
    }
    # espeak-ng-data — produced by ESPEAK_COMPILE_PHONEME_DATA at build.
    $espeakData = $null
    foreach ($cand in @("$espeakRoot\share\espeak-ng-data", "$espeakRoot\espeak-ng-data")) {
        if (Test-Path $cand) { $espeakData = $cand; break }
    }
    if ($espeakData) {
        $dst = Join-Path $runnerDir "espeak-ng-data"
        if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
        Copy-Item $espeakData $dst -Recurse -Force
        Write-Host "  bundled espeak-ng-data\ from $espeakData"
    } else {
        Write-Host "::error::espeak-ng-data dir not found under $espeakRoot" -ForegroundColor Red
    }
} else {
    Write-Host "  warn: ESPEAK_NG_ROOT not set — kokoro will be unusable" -ForegroundColor Yellow
}

Write-Host "`nFinal runner dir contents:"
Get-ChildItem $runnerDir -Filter *.dll | ForEach-Object { Write-Host "  $($_.Name)  $($_.Length) bytes" }
