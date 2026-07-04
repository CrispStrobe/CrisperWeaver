# CrisperWeaver v0.9.0 — CrispASR 0.8.7 + CrispEmbed 0.13.0 Integration

**Released:** 2026-07-04

This release integrates several months of development from the CrispASR
and CrispEmbed sibling repos into CrisperWeaver, adding cross-encoder
reranking, OCR, LoRA, streaming ASR callbacks, a Wyoming server, and
numerous catalog/model improvements.

---

## Highlights

### Semantic Search Upgrades
- **Cross-encoder reranker** — downloaded reranker models (MS MARCO,
  mxbai, BGE) automatically re-score top-k cosine results for higher
  search precision. The `rerankerProvider` probes for downloaded
  `ModelKind.reranker` GGUFs on startup.
- **BidirLM-Omni cross-modal search** — when the embedder supports
  audio (`hasAudio`), raw audio data is encoded into the shared
  text+audio embedding space for cross-modal retrieval.
- **imatrix embed defaults** — the recommended embedding model is now
  `all-MiniLM-L6-v2-iq4_xs` (19 MB IQ4_XS+imatrix), which is smaller
  and higher-cosine-fidelity than the previous Q8_0 default.

### TTS
- **Chatterbox emotion tags** — `[laugh]`, `[whispering]`, `[angry]`
  quick-insert buttons appear on the Synthesize screen when a
  Chatterbox model is selected.

### ASR
- **Qwen3-ASR-1.7B-JA** — Japanese anime/galgame speech fine-tune
  added to the model catalog.
- **Streaming segment callbacks** — LLM-based ASR backends (Qwen3,
  ARK, MOSS) now stream partial results during decode via
  `crispasr_drain_streamed_segments()` polling. The transcription
  screen fires `onSegment` in real-time instead of only after
  completion.
- **Engine version bumped** to 0.8.7; VAD empty-result guard verified.
- **.amr audio format** added to file picker and constants.

### OCR & Document Processing
- **OCR service** — `OcrService` wraps CrispEmbed's math OCR (pix2tex,
  HMER, BTTR, PosFormer) and VLM OCR (Granite Vision, DeepSeek-OCR2)
  via conditional imports (native FFI on desktop/mobile, stubs on web).
- **OCR image action** — "OCR image" in the transcript menu: pick an
  image, optionally preprocess (deskew/crop/whiten), run OCR, show
  result with copy-to-clipboard.
- **Scan preprocessing** — `ScanPreprocessService` wraps CrispEmbed's
  `CrispScanCleanup` for deskew, border crop, background whitening,
  and optional CNN denoising (NAFNet).

### Wyoming Protocol Server
- **Home Assistant STT** — `WyomingService` implements the Wyoming
  protocol over TCP, exposing CrisperWeaver's ASR as a Home Assistant
  speech-to-text provider. Audio streams in as base64 PCM chunks,
  transcript streams back as JSON.

### LoRA Hot-Swap
- **Dart FFI binding** added to CrispEmbed (`setLora`, `activeLora`,
  `listLora`, `hasLora`) with lazy symbol lookup for backward
  compatibility. Stubs and web implementation updated.

### Model Catalog
- **369 entries** from 120 HuggingFace repos (rebaked `catalog.json`).
- **6 OCR models** — pix2tex, HMER, BTTR, PosFormer, Granite Vision
  3.3 2B, DeepSeek-OCR2.
- **3 reranker models** — MS MARCO MiniLM-L6 (19 MB), mxbai XSmall
  (78 MB), BGE Reranker v2 M3 (613 MB, multilingual).
- **4 new embed models** — all-MiniLM-L6-v2 IQ4_XS+imatrix, Nomic
  Embed v1.5, Multilingual E5 Small, Qwen3 Embedding 0.6B.
- **Qwen3-ASR-1.7B-JA** anime fine-tune + BackendRepo.
- **2 new ModelKinds** — `ocr` and `reranker`.
- **12 new BackendRepos** for HF quant auto-discovery.

### Infrastructure
- **CrispEmbed stub parity** — `crispembed_stub.dart` and
  `crispembed_web.dart` updated to match CrispEmbed 0.13.0 API:
  reranker, sparse, ColBERT, vision, config, LoRA.
- **WASM IndexedDB caching** — web CrispEmbed caches downloaded
  models in IndexedDB for instant subsequent loads.
- **Embed provider fix** — `crispEmbedProvider` now searches both
  `crispasrBackendModels` and `whisperCppModels` so imatrix
  variants are found.
- **TADA re-align timestamps** — "Re-align timestamps" action in the
  transcript menu runs CTC forced alignment on existing transcript +
  audio without a full ASR pass.

---

## CrispASR Changes (pushed to CrispASR repo)
- `crispasr_segment_callback` typedef + `crispasr_session_set_segment_callback`
- `crispasr_get_streamed_segment_count`, `crispasr_drain_streamed_segments`,
  `crispasr_reset_streamed_segments` for Dart polling
- Dart binding: `getStreamedSegmentCount()`, `drainStreamedSegments()`,
  `resetStreamedSegments()`

## CrispEmbed Changes (pushed to CrispEmbed repo)
- LoRA Dart FFI binding (`setLora`, `getLora`, `listLora`)
- **fix:** use-after-free in `math_ocr.cpp` encoder/batch graph meta
  buffer — stack-local `std::vector<uint8_t>` backing the ggml context
  went out of scope while graph tensors still referenced it. Persisted
  as `ctx->enc_graph_meta` member.

---

## Test Results
- **1104 tests pass**, 23 skip (live tests without models), **0 failures**
- **+23 net new tests** since v0.8.7
- Live validation: embedding, reranker, LoRA API, OCR (quadratic
  formula recognition), CrispASR whisper transcription

## Breaking Changes
None. All new APIs are additive.

## Upgrade Notes
- Run `scripts/bake_models_catalog.dart` after updating to regenerate
  the catalog asset if building from source.
- The recommended embedding model changed from `all-MiniLM-L6-v2-Q8_0`
  to `all-MiniLM-L6-v2-iq4_xs` (smaller, better quality). Existing
  Q8_0 downloads continue to work.
