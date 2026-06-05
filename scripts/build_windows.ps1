# scripts/build_windows.ps1
#
# End-to-end Windows build:
#   1. (re)configure + build CrispASR's whisper.dll with every backend
#      statically linked in
#   2. flutter build windows
#   3. bundle whisper.dll + sibling backend DLLs + ggml DLLs next to
#      the runner exe via bundle_windows_dlls.ps1
#
# Usage:
#   pwsh -File scripts\build_windows.ps1 [debug|release] [-RebuildCmake]
#
#   Or via the convenience wrapper at the repo root:
#     build_windows.bat [debug|release] [-RebuildCmake]
#
# Env:
#   CRISPASR_DIR          path to sibling CrispASR repo
#                         (default: ..\CrispASR)
#   CRISPASR_BUILD_SUBDIR cmake binary dir under CRISPASR_DIR
#                         (default: build-flutter-bundle)
#
# The default subdir is "build-flutter-bundle" rather than "build" on
# purpose: the upstream CrispASR repo's `build\` is often configured
# for a different purpose (server, examples, sanitizer, etc.). Using a
# CrisperWeaver-specific subdir keeps our build options from fighting
# whatever else is in the same checkout.

param(
    [Parameter(Position=0)]
    [ValidateSet("debug","Debug","release","Release")]
    [string]$Config = "release",
    [switch]$RebuildCmake
)

$ErrorActionPreference = "Stop"

$flutterFlag    = if ($Config -ieq "debug") { "--debug" } else { "--release" }
$cmakeBuildType = "Release"
$runnerCfg      = if ($Config -ieq "debug") { "Debug" } else { "Release" }

$repoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$crispasrDir = if ($env:CRISPASR_DIR) {
    (Resolve-Path $env:CRISPASR_DIR).Path
} else {
    (Resolve-Path "$repoRoot\..\CrispASR").Path
}
$crispasrBuildSubdir = if ($env:CRISPASR_BUILD_SUBDIR) { $env:CRISPASR_BUILD_SUBDIR } else { "build-flutter-bundle" }
$buildDir = Join-Path $crispasrDir $crispasrBuildSubdir

if (-not (Test-Path $crispasrDir)) {
    Write-Error "Sibling CrispASR repo not at $crispasrDir. Clone it: git clone https://github.com/CrispStrobe/CrispASR `"$crispasrDir`""
    exit 3
}

Write-Host "==> CrispASR repo:    $crispasrDir"
Write-Host "==> CrispASR build:   $buildDir"
Write-Host "==> Flutter config:   $Config"

# ---------------------------------------------------------------------------
# Step 1: configure CrispASR (skip if cmake cache already exists, unless
# -RebuildCmake is passed).
# ---------------------------------------------------------------------------
$cacheFile = Join-Path $buildDir "CMakeCache.txt"
if ($RebuildCmake -or -not (Test-Path $cacheFile)) {
    Write-Host "==> cmake configure"
    if (Test-Path $buildDir) { Remove-Item -Recurse -Force $buildDir }
    & cmake -S $crispasrDir -B $buildDir `
        -DCMAKE_BUILD_TYPE=$cmakeBuildType `
        -DBUILD_SHARED_LIBS=ON `
        -DCRISPASR_BUILD_TESTS=OFF `
        -DCRISPASR_BUILD_EXAMPLES=OFF `
        -DCRISPASR_BUILD_SERVER=OFF
    if ($LASTEXITCODE -ne 0) { throw "cmake configure failed (exit $LASTEXITCODE)" }
}

# ---------------------------------------------------------------------------
# Step 2: build every backend STATIC archive plus the shared crispasr
# (whisper.dll). Mirrors the macOS flow in build_macos.sh: backends
# linked via runtime `if (TARGET ...)` checks have to be built first
# so crispasr's link step picks them up.
# ---------------------------------------------------------------------------
$backendTargets = @(
    # ASR
    "parakeet","canary","canary_ctc","qwen3_asr","cohere","granite_speech","granite_nle",
    "voxtral","voxtral4b","wav2vec2-ggml","glm-asr","kyutai-stt","firered-asr",
    "funasr","paraformer","sensevoice","omniasr",
    "moonshine","moonshine_streaming","gemma4_e2b","mimo_tokenizer","mimo_asr","vibevoice",
    # TTS
    "qwen3_tts","orpheus","chatterbox","indextts","kokoro","piper-tts",
    "voxcpm2_tts","cosyvoice3_tts","f5-tts","outetts",
    "bark-tts","csm-tts","dia-tts","fastpitch-tts","parler-tts","speecht5-tts",
    "pocket-tts","zonos-tts","melotts","bert-encoder","openvoice2","kugelaudio",
    # Translation
    "m2m100","t5_translate",
    # Post-processing & LID
    "fireredpunc","pcs","truecaser","truecaser_crf","truecaser_lstm",
    "pyannote-seg","silero-lid","ecapa-lid","firered-lid","firered-vad","marblenet-vad",
    "crispasr-vad-encdec","titanet","ctc-align",
    "lid-cld3","lid-fasttext","text-lid-dispatch"
)

Write-Host "==> build backend statics ($($backendTargets.Count) targets)"
& cmake --build $buildDir --config $cmakeBuildType --parallel --target $backendTargets
if ($LASTEXITCODE -ne 0) { throw "backend build failed (exit $LASTEXITCODE)" }

Write-Host "==> link whisper.dll"
& cmake --build $buildDir --config $cmakeBuildType --parallel --target crispasr
if ($LASTEXITCODE -ne 0) { throw "crispasr (whisper.dll) link failed (exit $LASTEXITCODE)" }

# ---------------------------------------------------------------------------
# Step 3: flutter build
# ---------------------------------------------------------------------------
Push-Location $repoRoot
try {
    Write-Host "==> flutter pub get"
    & flutter pub get | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed (exit $LASTEXITCODE)" }

    Write-Host "==> flutter build windows $flutterFlag"
    & flutter build windows $flutterFlag
    if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed (exit $LASTEXITCODE)" }

    $runnerDir = Join-Path $repoRoot "build\windows\x64\runner\$runnerCfg"
    if (-not (Test-Path $runnerDir)) {
        throw "Runner dir not found at $runnerDir after flutter build"
    }

    # ---------------------------------------------------------------------
    # Step 4: bundle DLLs next to the runner exe
    # ---------------------------------------------------------------------
    Write-Host "==> bundle DLLs"
    $env:CRISPASR_DIR          = $crispasrDir
    $env:CRISPASR_BUILD_SUBDIR = $crispasrBuildSubdir
    $env:RUNNER_DIR            = $runnerDir
    & "$repoRoot\scripts\bundle_windows_dlls.ps1"
    if ($LASTEXITCODE -ne 0) { throw "DLL bundling failed (exit $LASTEXITCODE)" }

    $exePath = Join-Path $runnerDir "crisper_weaver.exe"
    Write-Host ""
    Write-Host "==> done: $exePath"
    Write-Host "    Run it with:  & '$exePath'"
} finally {
    Pop-Location
}
