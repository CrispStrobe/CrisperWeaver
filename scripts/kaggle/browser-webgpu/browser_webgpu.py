#!/usr/bin/env python3
"""One physical-GPU WebGPU assessment; no native build and no GPU fishing."""
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys

VERSION = 'browser-webgpu-v1'
CW_REF = 'e0ce006bfda9dccf59cc94b72849ead0b112dfbd'
WORK = Path('/kaggle/working')
SCRATCH = Path('/tmp/cw-webgpu')
SCRATCH.mkdir(parents=True, exist_ok=True)
ASR = SCRATCH / 'CrispASR'
subprocess.run(['git', 'clone', '--depth', '1', 'https://github.com/CrispStrobe/CrispASR.git', str(ASR)], check=True)
sys.path.insert(0, str(ASR / 'tools/kaggle'))
import kaggle_harness as kh
kh.init_progress(WORK / 'progress.jsonl')
kh.provenance(VERSION, ASR)
evidence = {'scriptVersion': VERSION, 'cwRef': CW_REF, 'conclusiveGpuInference': False,
            'scope': 'Shared Full/Lite speech worker assets; Flutter UI is validated separately by GitHub CI.'}


def run(argv, cwd=None, timeout=900, check=True, capture=False):
    kh.step('command', executable=argv[0], arguments=argv[1:])
    return subprocess.run(argv, cwd=cwd, timeout=timeout, check=check,
                          capture_output=capture, text=True)


try:
    evidence['nvidia'] = run(['nvidia-smi', '--query-gpu=name,uuid,driver_version,compute_cap', '--format=csv,noheader'], capture=True).stdout.strip()
    run(['apt-get', 'update', '-qq'])
    run(['apt-get', 'install', '-y', '-qq', '--no-install-recommends', 'vulkan-tools', 'libvulkan1'])
    probe = run(['vulkaninfo', '--summary'], check=False, capture=True)
    evidence['vulkanInitial'] = probe.stdout + probe.stderr
    if not any(re.search(r'deviceName\s*=.*(?:NVIDIA|Tesla)', line) for line in evidence['vulkanInitial'].splitlines()):
        major = run(['nvidia-smi', '--query-gpu=driver_version', '--format=csv,noheader'], capture=True).stdout.split('.')[0].strip()
        if major.isdigit():
            install = run(['apt-get', 'install', '-y', '-qq', '--no-install-recommends', f'libnvidia-gl-{major}'], check=False)
            evidence['driverLibraryInstallExit'] = install.returncode
        probe = run(['vulkaninfo', '--summary'], check=False, capture=True)
    evidence['vulkan'] = probe.stdout + probe.stderr
    if not any(re.search(r'deviceName\s*=.*(?:NVIDIA|Tesla)', line) for line in evidence['vulkan'].splitlines()):
        raise RuntimeError('Physical NVIDIA GPU exists, but Vulkan cannot expose it. WebGPU inference is unvalidated; stop without a software benchmark or another GPU draw.')
    CW = SCRATCH / 'CrisperWeaver'
    run(['git', 'clone', '--depth', '1', '--branch', 'feat/browser-hardening', 'https://github.com/CrispStrobe/CrisperWeaver.git', str(CW)])
    run(['git', 'fetch', '--depth', '1', 'origin', CW_REF], cwd=CW)
    run(['git', 'checkout', '--detach', 'FETCH_HEAD'], cwd=CW)
    evidence['cwSha'] = run(['git', 'rev-parse', 'HEAD'], cwd=CW, capture=True).stdout.strip()
    # No Flutter compilation on the GPU runner: copy shipped runtime assets.
    APP = CW / 'build/web'
    shutil.copytree(CW / 'web/speech', APP / 'speech', dirs_exist_ok=True)
    APP.mkdir(parents=True, exist_ok=True)
    (APP / 'index.html').write_text('<!doctype html><html><head><script src="/speech/bridge.js"></script></head><body>Shared local speech runtime GPU assessment</body></html>')
    run(['npm', 'ci'], cwd=CW / 'web-e2e')
    run(['bash', 'scripts/build_browser_runtime.sh'], cwd=CW)
    run(['npx', 'playwright', 'install', '--with-deps', 'chromium'], cwd=CW / 'web-e2e')
    server_log = (WORK / 'server.log').open('w')
    server = subprocess.Popen([sys.executable, 'scripts/serve_browser_test.py', '--app', str(APP), '--port', '8766'], cwd=CW, stdout=server_log, stderr=subprocess.STDOUT)
    try:
        env = dict(os.environ, BASE_URL='http://127.0.0.1:8766', REQUIRE_HARDWARE_GPU='1',
                   BENCHMARK_MODELS='onnx:onnx-moonshine-tiny,onnx:onnx-tiny.en',
                   BENCHMARK_PROVIDERS='wasm,webgpu', BENCHMARK_REPETITIONS='3',
                   BENCHMARK_BROWSER_ARGS=json.dumps(['--use-angle=vulkan', '--enable-features=Vulkan', '--disable-vulkan-surface', '--ignore-gpu-blocklist']))
        completed = subprocess.run(['node', 'scripts/benchmark_browser_models.mjs'], cwd=CW, env=env, timeout=1800)
        report = CW / 'web-e2e/artifacts/model-benchmark/results.json'
        if report.exists(): shutil.copy2(report, WORK / 'browser-gpu-results.json')
        evidence['benchmarkExit'] = completed.returncode
        evidence['conclusiveGpuInference'] = completed.returncode == 0
        if completed.returncode: raise RuntimeError('Browser GPU assessment failed; inspect adapter/provider evidence. CPU fallback does not pass GPU validation.')
    finally:
        server.terminate(); server.wait(timeout=30); server_log.close()
except Exception as error:
    evidence['error'] = str(error)
    kh.step('gpu-assessment-failed', reason=str(error))
finally:
    (WORK / 'gpu-assessment.json').write_text(json.dumps(evidence, indent=2))
    kh.step('gpu-assessment-complete', passed=evidence['conclusiveGpuInference'])
if not evidence['conclusiveGpuInference']:
    raise SystemExit(1)
