#!/usr/bin/env python3
"""CrisperWeaver §5.24D / §9.2 live validation on Kaggle GPU.

Tests the three PLAN.md items that are blocked on model availability:
  1. Local-LLM cleanup/summarize (gemma4-e2b-it-q4_k, 2.6 GB)
  2. Speech-to-speech (lfm2-audio-1.5b-q5_k, ~1 GB)
  3. M2M100 translation (m2m100-418m-q8_0, ~500 MB)

All tests run via the CrispASR CLI (`crispasr` binary).

Run:  push to Kaggle via `python -m kaggle kernels push -p .`
"""

import subprocess, sys, os, json, time
from pathlib import Path

WORK = Path("/kaggle/working")
CRISPASR_URL = "https://github.com/CrispStrobe/CrispASR.git"
_CRISPASR_DIR = WORK / "CrispASR"

# ── Bootstrap ──────────────────────────────────────────────────
print("=== CrisperWeaver Live Validation ===", flush=True)

if not _CRISPASR_DIR.exists():
    try:
        subprocess.check_call(["git", "clone", "--depth", "1",
            "--recurse-submodules", "--shallow-submodules",
            CRISPASR_URL, str(_CRISPASR_DIR)])
        sys.path.insert(0, str(_CRISPASR_DIR / "tools" / "kaggle"))
    except Exception:
        pass

if str(_CRISPASR_DIR / "tools" / "kaggle") not in sys.path:
    sys.path.insert(0, str(Path(__file__).resolve().parent))

import kaggle_harness as kh
kh.init_progress()

# ── Build CrispASR ─────────────────────────────────────────────
print("\n=== Building CrispASR ===", flush=True)
kh.install_build_toolchain()
arch = kh.detect_cuda_arch()
cuda_flags = kh.cuda_build_flags(arch)
cache_flags = kh.cache_and_link_flags()
jobs = kh.safe_build_jobs(gpu=True)

build_dir = WORK / "crispasr-build"
build_dir.mkdir(exist_ok=True)

cmake_cmd = [
    "cmake", "-S", str(_CRISPASR_DIR), "-B", str(build_dir),
    "-DCMAKE_BUILD_TYPE=Release",
    "-DGGML_CUDA=ON",
    f"-DCMAKE_CUDA_ARCHITECTURES={arch}",
    *cuda_flags, *cache_flags,
]
subprocess.check_call(cmake_cmd)
kh.build_heartbeat("crispasr")
subprocess.check_call(["cmake", "--build", str(build_dir), "-j", str(jobs),
                        "--target", "crispasr-cli"])

CRISPASR_BIN = str(build_dir / "bin" / "crispasr")
assert os.path.exists(CRISPASR_BIN), f"binary not found: {CRISPASR_BIN}"
print(f"✓ Built: {CRISPASR_BIN}", flush=True)

# ── Download models ────────────────────────────────────────────
print("\n=== Downloading models ===", flush=True)

hf_token = kh.hf_token()
if hf_token:
    os.environ["HF_TOKEN"] = hf_token

subprocess.check_call([sys.executable, "-m", "pip", "install", "-q",
                        "huggingface_hub"])
from huggingface_hub import hf_hub_download

MODELS_DIR = WORK / "models"
MODELS_DIR.mkdir(exist_ok=True)

models = {
    # LLM cleanup/summarize
    "gemma4-e2b": {
        "repo": "cstr/gemma4-e2b-it-GGUF",
        "file": "gemma4-e2b-it-q4_k.gguf",
    },
    # Speech-to-speech
    "lfm2-audio": {
        "repo": "cstr/lfm2-audio-1.5b-GGUF",
        "file": "lfm2-audio-1.5b-q5_k.gguf",
    },
    # Translation
    "m2m100": {
        "repo": "cstr/m2m100-GGUF",
        "file": "m2m100-418m-q8_0.gguf",
    },
    # ASR (needed as base for LLM cleanup test)
    "whisper-tiny": {
        "repo": "ggerganov/whisper.cpp",
        "file": "ggml-tiny.bin",
    },
}

model_paths = {}
for name, spec in models.items():
    print(f"  Downloading {name}: {spec['file']}...", end=" ", flush=True)
    try:
        path = hf_hub_download(
            repo_id=spec["repo"],
            filename=spec["file"],
            local_dir=str(MODELS_DIR),
            token=hf_token,
        )
        model_paths[name] = path
        size_mb = os.path.getsize(path) / (1024 * 1024)
        print(f"✓ ({size_mb:.0f} MB)", flush=True)
    except Exception as e:
        print(f"✗ ({e})", flush=True)
        model_paths[name] = None

# Generate a test audio file (JFK sample from CrispASR)
JFK_WAV = str(_CRISPASR_DIR / "samples" / "jfk.wav")
assert os.path.exists(JFK_WAV), f"jfk.wav not found: {JFK_WAV}"

# ── Write progress file ───────────────────────────────────────
results = {}

def run_test(name, cmd, check_output=None, timeout=300):
    """Run a CLI test and record pass/fail."""
    print(f"\n=== Test: {name} ===", flush=True)
    print(f"  cmd: {' '.join(cmd)}", flush=True)
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        print(f"  exit: {r.returncode}", flush=True)
        if r.stdout:
            print(f"  stdout: {r.stdout[:500]}", flush=True)
        if r.stderr:
            print(f"  stderr (last 300): ...{r.stderr[-300:]}", flush=True)

        passed = r.returncode == 0
        if check_output and passed:
            passed = check_output(r.stdout)

        results[name] = "PASS" if passed else f"FAIL (exit={r.returncode})"
        print(f"  → {'PASS' if passed else 'FAIL'}", flush=True)
    except subprocess.TimeoutExpired:
        results[name] = "TIMEOUT"
        print(f"  → TIMEOUT ({timeout}s)", flush=True)
    except Exception as e:
        results[name] = f"ERROR: {e}"
        print(f"  → ERROR: {e}", flush=True)

# ── Test 1: Basic ASR (baseline sanity check) ─────────────────
if model_paths.get("whisper-tiny"):
    run_test("whisper-tiny-transcribe", [
        CRISPASR_BIN, "-m", model_paths["whisper-tiny"],
        "-f", JFK_WAV,
    ], check_output=lambda out: "ask not" in out.lower() or "country" in out.lower())
else:
    results["whisper-tiny-transcribe"] = "SKIP (model not downloaded)"

# ── Test 2: Local-LLM cleanup/summarize ───────────────────────
if model_paths.get("gemma4-e2b"):
    # First transcribe, then pass to the chat LLM for cleanup
    run_test("gemma4-e2b-chat", [
        CRISPASR_BIN, "-m", model_paths["gemma4-e2b"],
        "--backend", "gemma4-e2b",
        "-f", JFK_WAV,
    ], timeout=600,
    check_output=lambda out: len(out.strip()) > 10)
else:
    results["gemma4-e2b-chat"] = "SKIP (model not downloaded)"

# ── Test 3: Speech-to-speech ──────────────────────────────────
if model_paths.get("lfm2-audio"):
    run_test("lfm2-audio-s2s", [
        CRISPASR_BIN, "-m", model_paths["lfm2-audio"],
        "--backend", "lfm2-audio",
        "-f", JFK_WAV,
    ], timeout=600,
    check_output=lambda out: len(out.strip()) > 5)
else:
    results["lfm2-audio-s2s"] = "SKIP (model not downloaded)"

# ── Test 4: M2M100 translation ────────────────────────────────
if model_paths.get("m2m100"):
    # Translate a known English phrase to German
    run_test("m2m100-en-de", [
        CRISPASR_BIN, "-m", model_paths["m2m100"],
        "--backend", "m2m100",
        "--translate",
        "-l", "en",
        "--target-language", "de",
        "-f", JFK_WAV,
    ], timeout=600,
    check_output=lambda out: len(out.strip()) > 5)
else:
    results["m2m100-en-de"] = "SKIP (model not downloaded)"

# ── Summary ───────────────────────────────────────────────────
print("\n" + "=" * 60, flush=True)
print("RESULTS SUMMARY", flush=True)
print("=" * 60, flush=True)
for name, status in results.items():
    icon = "✓" if status == "PASS" else "✗" if "FAIL" in status else "⊘"
    print(f"  {icon} {name}: {status}", flush=True)

passed = sum(1 for s in results.values() if s == "PASS")
total = len(results)
print(f"\n{passed}/{total} passed", flush=True)

# Write results to file for download
with open(WORK / "results.json", "w") as f:
    json.dump(results, f, indent=2)
with open(WORK / "progress.txt", "w") as f:
    f.write(f"DONE: {passed}/{total} passed\n")
    for name, status in results.items():
        f.write(f"  {name}: {status}\n")

print("\nDone.", flush=True)
