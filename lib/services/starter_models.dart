// Curated starter picks and device-fit gating for the Models screen.
//
// WHY THIS EXISTS
//
// The catalogue is 367 models across 10 kinds, harvested from HuggingFace.
// That is a good library and a bad first screen. Before this file, a new
// install landed on "no models downloaded yet" → a list of 367 entries with
// no indication that `moonshine-base-q4_k` (47 MB) is a sane first pick and
// `MiMo ASR (f16)` (16 GB) will not load on any phone ever made.
//
// Two separate problems, and it is worth keeping them apart:
//
//   1. **Nothing was recommended.** Filters answer "which of these is a
//      Parakeet?", not "which should I take?". [recommendedFor] answers the
//      second, per kind, ordered.
//   2. **Nothing was refused.** 150 catalogue entries exceed 1 GB and 90
//      exceed 2 GB, while `MemoryEstimator` assumes 3 GB on iOS. That
//      estimator existed but was wired only to the worker-count slider — so
//      the app would carefully refuse to run two workers against a 400 MB
//      model, then happily download 16 GB and OOM on load. [fitFor] closes
//      that.
//
// Both are onboarding fixes, but the second is a crash fix: an OOM on a
// TestFlight build is what Beta App Review rejects.
import 'memory_estimator.dart';
import 'model_catalog.dart' show ModelKind;

/// How a model relates to the memory the device actually has.
enum DeviceFit {
  /// Loads with room to spare.
  comfortable,

  /// Will probably load, but leaves little headroom — the OS may evict the
  /// app when it backgrounds, and a second model (diarisation, punctuation)
  /// on top of it may not fit.
  tight,

  /// Larger than the device can hold. Downloading is allowed but confirmed,
  /// because the bytes are the user's to spend and a wrong RAM estimate
  /// should not be a hard wall — see [budgetBytes].
  tooLarge,

  /// RAM could not be read. Nothing is claimed, and nothing is blocked.
  unknown,
}

class StarterModels {
  StarterModels._();

  /// Ordered starter picks per kind, most-recommended first.
  ///
  /// Hand-curated rather than derived, because "recommended" is a judgement
  /// about quality-per-megabyte that no catalogue field carries. Chosen to be
  /// small enough for a phone, broad enough in language coverage to be worth
  /// a first try, and permissively licensed.
  ///
  /// Entries that are not in the catalogue are skipped silently by
  /// [recommendedFor], so a retired model id degrades to a shorter list
  /// rather than an error — and `test/starter_models_test.dart` asserts every
  /// id here still resolves, so it degrades in CI first.
  static const Map<ModelKind, List<String>> _picks = {
    ModelKind.asr: [
      // whisper.cpp base q5_0 — the reference starter: multilingual, ~60 MB,
      // and the backend with the widest platform coverage in this app.
      'base-q5_0',
      // Moonshine base — faster than whisper at similar size, English-first.
      'moonshine-base-q4_k',
      // Parakeet 110M — CTC, very fast, good on short clips.
      'parakeet-tdt_ctc-110m-q4_k',
      // A step up in accuracy for anyone with the headroom.
      'parakeet-tdt-0.6b-v3-q4_k',
    ],
    ModelKind.tts: [
      // Kokoro — the best quality-per-megabyte TTS in the catalogue.
      'kokoro-82m-q8_0',
      // Piper. Deliberately **thorsten** and **cori** and not `lessac`:
      // lessac is Blizzard-Challenge research-only, and recommending it from
      // inside the app would be pointing users at a licence the project does
      // not itself rely on. These two are the CC0 / public-domain voices.
      'piper-de_DE-thorsten-medium-f16',
      'piper-en_GB-cori-medium-f16',
    ],
  };

  /// Curated model ids for [kind], most-recommended first.
  ///
  /// Ids rather than resolved objects, because the Models screen works in
  /// `ModelInfo` (catalogue merged with what is on disk) while the catalogue
  /// itself is `ModelDefinition`. Returning ids lets the caller partition
  /// whatever list it already has, and keeps this file free of both types.
  static List<String> pickIdsFor(ModelKind kind) => _picks[kind] ?? const [];

  /// Whether [kind] has any curated picks at all — the Models screen hides
  /// the Recommended section rather than rendering an empty header.
  static bool hasPicksFor(ModelKind kind) => _picks.containsKey(kind);

  /// Rank of [id] within its kind's picks, or `-1`. Lets a caller sort a
  /// filtered list back into curated order.
  static int rankOf(ModelKind kind, String id) =>
      (_picks[kind] ?? const []).indexOf(id);

  /// Every curated id, for the test that keeps this list honest.
  static List<String> get allPickIds =>
      _picks.values.expand((e) => e).toList(growable: false);

  /// Memory the app can realistically give one model, in bytes.
  ///
  /// Derived from the same constants the worker-count pre-flight uses, so the
  /// two cannot disagree about the same device:
  /// [MemoryEstimator.memoryHeadroomFraction] of physical RAM, less the base
  /// resident set the app occupies before any model loads.
  static int? budgetBytes(MemoryEstimator estimator) {
    final ram = estimator.physicalMemoryBytes();
    if (ram == null || ram <= 0) return null;
    final usable =
        (ram * MemoryEstimator.memoryHeadroomFraction).round() -
            MemoryEstimator.baseRssBytes;
    return usable > 0 ? usable : 0;
  }

  /// How [sizeBytes] of model weights relate to what the device can hold.
  ///
  /// A GGUF needs more than its file size resident — KV cache, activations,
  /// and the runtime's own allocations — which is what
  /// [MemoryEstimator.modelOverheadMultiplier] accounts for. Using the same
  /// multiplier here means a model marked comfortable is one the worker
  /// pre-flight will also accept.
  static DeviceFit fitFor(int sizeBytes, MemoryEstimator estimator) {
    if (sizeBytes <= 0) return DeviceFit.unknown;
    final budget = budgetBytes(estimator);
    if (budget == null || budget <= 0) return DeviceFit.unknown;
    final needed =
        (sizeBytes * MemoryEstimator.modelOverheadMultiplier).round();
    if (needed > budget) return DeviceFit.tooLarge;
    // Within 75% of the budget is "it fits, but do not expect to stack
    // diarisation and punctuation on top of it".
    if (needed > budget * 0.75) return DeviceFit.tight;
    return DeviceFit.comfortable;
  }
}
