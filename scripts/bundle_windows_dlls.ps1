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
    throw "whisper.dll not found under $cBase. Run scripts\build_windows.ps1 (or `cmake --build $crispasrBuildSubdir --config Release --target crispasr-lib`) first."
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

# Opus/Ogg codec runtime. With CRISPASR_OPUS_FETCH=ON + BUILD_SHARED_LIBS=ON,
# libopus + libopusfile's libogg build as separate DLLs (opus.dll, ogg.dll)
# that crispasr.dll IMPORTS (opusfile, for native .opus decode). Without
# them crispasr.dll fails to load with Windows error 126 ("specified module
# could not be found") — even though crispasr.dll itself is present — which
# is exactly the #30 "built with {}" / error-126 report. These are REQUIRED,
# not optional: warn loudly if missing so the guard below catches it.
foreach ($c in @("opus", "ogg")) {
    $dll = Find-Dll $cBase $c
    if ($dll) {
        Copy-Item $dll "$runnerDir\$c.dll" -Force
        Write-Host "  bundled $c.dll"
    } else {
        Write-Host "::warning::$c.dll not found under $cBase — crispasr.dll may fail to load (error 126) if it imports it" -ForegroundColor Yellow
    }
}

# glint codec DLL (on-device MP3 / AAC-LC / Opus). Self-contained (no
# extra runtime deps), so just drop it next to the runner exe where the
# Dart loader's `DynamicLibrary.open('glint.dll')` finds it. Non-fatal —
# the app falls back to WAV/ffmpeg at runtime when it's absent.
$glintDir = if ($env:GLINT_DIR) { $env:GLINT_DIR } else { "..\glint" }
$glintDll = $null
foreach ($cand in @(
    "$glintDir\build\Release\glint.dll",
    "$glintDir\build\glint.dll")) {
    if (Test-Path $cand) { $glintDll = $cand; break }
}
if ($glintDll) {
    Copy-Item $glintDll "$runnerDir\glint.dll" -Force
    Write-Host "  bundled glint.dll from $glintDll"
} else {
    Write-Host "  warn: glint.dll not found under $glintDir; MP3/AAC/Opus codec disabled (app falls back to WAV/ffmpeg)" -ForegroundColor Yellow
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
    # MSVC drops the `lib` prefix on shared libs — the file is
    # `espeak-ng.dll`, not `libespeak-ng.dll`. whisper.dll's import
    # table NEEDs `espeak-ng.dll` (matches the LINK_NAME at build
    # time), so bundle it under that name. We also drop a copy under
    # `libespeak-ng.dll` for any caller still using the Unix name.
    $espeakDll = $null
    foreach ($cand in @(
        "$espeakRoot\bin\espeak-ng.dll",
        "$espeakRoot\bin\libespeak-ng.dll",
        "$espeakRoot\espeak-ng.dll",
        "$espeakRoot\libespeak-ng.dll")) {
        if (Test-Path $cand) { $espeakDll = $cand; break }
    }
    if ($espeakDll) {
        $dllBase = [System.IO.Path]::GetFileName($espeakDll)
        Copy-Item $espeakDll "$runnerDir\$dllBase" -Force
        Write-Host "  bundled $dllBase from $espeakDll"
        # Provide the alternate name too — cheap insurance against
        # whisper.dll being relinked under either NEEDED string.
        if ($dllBase -eq "libespeak-ng.dll") {
            Copy-Item $espeakDll "$runnerDir\espeak-ng.dll" -Force
        } elseif ($dllBase -eq "espeak-ng.dll") {
            Copy-Item $espeakDll "$runnerDir\libespeak-ng.dll" -Force
        }
    } else {
        Write-Host "::error::espeak-ng DLL not found under $espeakRoot" -ForegroundColor Red
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

# --- Dependency sanity check (mirrors the Android NEEDED-deps guard) ---
# Verify every non-system DLL that crispasr.dll imports is present next to
# runner.exe. This is what would have caught the opus.dll / ogg.dll gap
# that shipped as Windows "error 126" (#30 follow-up) at BUILD time instead
# of on a user's machine. dumpbin ships with MSVC on the runner.
$dumpbin = Get-Command dumpbin -ErrorAction SilentlyContinue
if ($dumpbin) {
    $deps = & dumpbin /dependents "$runnerDir\crispasr.dll" 2>$null |
        Select-String -Pattern '^\s{2,}([A-Za-z0-9_.\-]+\.dll)\s*$' |
        ForEach-Object { $_.Matches[0].Groups[1].Value }
    # DLLs provided by Windows itself or the VC++ redistributable — not our
    # job to bundle. Matched case-insensitively as prefixes.
    $systemPrefixes = @('kernel32','advapi32','ole32','shell32','user32',
        'gdi32','ws2_32','bcrypt','crypt32','msvcp140','vcruntime140',
        'vcomp140','concrt140','api-ms-','ext-ms-','ucrtbase','ntdll',
        'winmm','oleaut32','shlwapi','dbghelp','secur32','rpcrt4','iphlpapi',
        'userenv','psapi','powrprof','dwmapi','setupapi','cfgmgr32','d3d11',
        'dxgi','mfplat','mf.dll','mfreadwrite','avrt','ksuser','dnsapi')
    $missing = @()
    foreach ($d in $deps) {
        $isSystem = $false
        foreach ($p in $systemPrefixes) {
            if ($d.ToLower().StartsWith($p.ToLower())) { $isSystem = $true; break }
        }
        if ($isSystem) { continue }
        if (-not (Test-Path (Join-Path $runnerDir $d))) { $missing += $d }
    }
    if ($missing.Count -gt 0) {
        Write-Host "::error::crispasr.dll imports DLL(s) missing from the bundle: $($missing -join ', ') — these cause Windows error 126 (can't load crispasr.dll) on user machines. Add them to this script's copy list."
        exit 1
    }
    Write-Host "  OK: every non-system DLL crispasr.dll imports is bundled"
} else {
    Write-Host "  warn: dumpbin not on PATH — skipped the crispasr.dll dependency check" -ForegroundColor Yellow
}
