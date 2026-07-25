# Windows Tesla P100 CUDA build

The prebuilt Windows package may contain only the CPU ggml backend. A Tesla
P100 also needs CUDA kernels compiled for Pascal compute capability 6.0
(`sm_60`); a CUDA build that contains only newer architectures cannot execute
those kernels on a P100.

This build mode is intentionally opt-in. It does not change the normal CPU
build or the release workflow.

## Prerequisites

- NVIDIA Tesla P100 with a current NVIDIA driver
- CUDA Toolkit 12.x (12.4 and 12.8 are known to support `sm_60`)
- Visual Studio 2022 C++ Build Tools
- CMake and Ninja on `PATH`
- Flutter and the sibling repositories listed in the main README

CUDA 13 must not be used because it no longer generates code for Pascal GPUs.

## Build

Open **x64 Native Tools Command Prompt for VS 2022**, then run:

```bat
set "CUDA_PATH=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.4"
set "PATH=%CUDA_PATH%\bin;%PATH%"

cd /d C:\path\to\CrisperWeaver
pwsh -File scripts\build_windows.ps1 release -P100
```

`-P100` uses a separate `build-flutter-p100` CrispASR build directory and
configures:

```text
GGML_CUDA=ON
GGML_CUDA_NO_VMM=ON
GGML_CUDA_NCCL=OFF
GGML_NATIVE=OFF
CMAKE_CUDA_ARCHITECTURES=60
```

Ninja is selected explicitly so CUDA compilation does not depend on the
optional Visual Studio CUDA toolset integration.

The bundler copies `ggml-cuda.dll` and its CUDA 12 runtime dependencies next
to `crisper_weaver.exe`. This makes the result independent of the shell's
`PATH`; an NVIDIA display driver is still required on the target machine.

## Verify

The runner directory should contain at least:

```text
crisper_weaver.exe
crispasr.dll
ggml.dll
ggml-base.dll
ggml-cpu.dll
ggml-cuda.dll
cudart64_12.dll
cublas64_12.dll
cublasLt64_12.dll
nvJitLink_*.dll
```

At startup, CrispASR should report a CUDA device with compute capability 6.0.
When a supported model is loaded, its log should report that the CUDA backend
is active. Some audio preprocessing can remain on the CPU; that alone does not
mean GPU offload failed.

If startup reports `no kernel image is available for execution on the
device`, remove the P100 build directory and rebuild with `-P100
-RebuildCmake`. That error means the loaded CUDA backend was not compiled for
`sm_60`.
