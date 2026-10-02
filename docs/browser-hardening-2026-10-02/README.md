# Browser hardening evidence — 2026-10-02

These reports use real models and audio. The standard and Phonon reports came
from GitHub Actions run [37008639394](https://github.com/CrispStrobe/CrisperWeaver/actions/runs/37008639394).
Each mode has a cold load and three independently loaded warm runs.

| Model | Old single-thread median | 128 MiB SIMD median | Four-thread SIMD median |
| --- | ---: | ---: | ---: |
| Whisper tiny English | 20,002 ms | 7,940 ms | 3,362 ms |
| Whisper base | 49,481 ms | 17,995 ms | 7,786 ms |
| Moonshine Q4 | 1,872 ms | 1,267 ms | 3,099 ms |
| FastConformer Q4 | 7,269 ms | 3,806 ms | 4,450 ms |
| Phonon Q4 | 31,409 ms | 12,204 ms | 8,303 ms |

All decoded transcripts match their same-model old CPU baseline. The newer
variants enable WASM SIMD as well as reducing initial memory, so the timing
improvement must not be attributed to the heap setting alone. Four threads
are useful for Phonon and slower for Moonshine; the application keeps one
thread by default. All five native models pass decoded parity and three-warm-
run timing comparisons; the smaller initial-heap SIMD runtime is now the
default. Set `cw.browserLowMemoryRuntime=false` to compare the older runtime.

Memory figures sample the sum of Chromium process-tree RSS, including the
browser baseline and shared pages counted per process. They are neither live
model allocations nor GPU memory. Phonon peaks near 2.5 GB in every mode;
its smaller initial WASM allocation does not deliver a meaningful peak RSS
reduction. Whisper tiny also grows beyond its initial allocation and its
process RSS is slightly higher with the smaller heap; the runtime change is
primarily a latency improvement for that model. These measurements do not guarantee that a constrained browser or
mobile device can run Phonon.

The ONNX GPU requests in these hosted CPU-runner reports fell back to WASM.
They are CPU measurements. A separate physical Tesla T4 assessment exposed
incorrect q8 Moonshine output and a q8 Whisper alignment failure. The worker
now requests fp32 GPU weights and retries failed inference in a fresh CPU
worker; the physical reassessment passes on Tesla T4 with actual WebGPU execution,
three warm runs and decoded transcript parity for Moonshine tiny and Whisper
tiny English. See `physical-gpu-benchmark.json` and
`physical-gpu-assessment.json`. A CPU fallback cannot satisfy
physical-GPU validation. Warm medians: Moonshine CPU q8 1,758 ms versus GPU
fp32 2,046 ms; Whisper tiny English CPU q8 4,428 ms versus GPU fp32 1,925 ms.
Precision differs between providers; this measures each supported execution
path, not equivalent-precision kernel speed. The GPU remains optional: one
NVIDIA driver/model pair does not validate all devices or every catalogue
model. GPU memory samples are device-wide and may include other processes.

Runtime regression coverage passes two/four-thread ASR, downloads-disabled
worker reload and cancellation in Chromium, Firefox and WebKit. All three
pass four-thread Kokoro synthesis followed by Moonshine ASR. All twelve
quota, interrupted-download, eviction and missing-chunk recovery checks pass.
Verified models of every size use IndexedDB chunks: WebKit dedicated-worker
CacheStorage entries disappeared after worker termination in a real probe,
while IndexedDB checkpoints survived.

Continuous English and noisy French/German recordings have separate retained-
utterance, timestamp and WER checks. French/German small-model isolated WER is
high (roughly 52–55% in the initial Chromium sample); retention parity against
that baseline is not a claim of high multilingual transcription accuracy.
