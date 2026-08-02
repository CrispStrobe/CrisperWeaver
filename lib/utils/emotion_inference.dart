// EU AI Act — the emotion tags this app refuses to surface.
//
// SenseVoice emits inline `<|HAPPY|>` / `<|SAD|>` / `<|ANGRY|>` tags
// alongside the transcript. CrisperWeaver used to parse them into
// `metadata['emotion']` and render a per-segment badge, which made it an
// *emotion recognition system* under Art. 3(39): inferring the emotional
// state of a natural person from biometric data (voice).
//
// `docs/AI_ACT_RISK.md` §3.3 asserted the opposite through two audits —
// "no emotion recognition is performed" — because the claim was checked
// against the synthesis screen's Chatterbox prosody tags and never against
// the ASR engine. The third audit (2026-08-02) found the recognition side
// and the feature was **removed** rather than documented.
//
// Why removed and not disclosed. Art. 50(3) transparency would have been
// the cheap part. The expensive part is Annex III **1(c)**, which lists
// emotion recognition as high-risk with no verification-style carve-out to
// fall outside of — bringing risk management, logging, human oversight and
// conformity assessment from 2 Dec 2027, plus Art. 49(2) registration if
// the Art. 6(3) derogation were relied on. That is a large permanent
// obligation for a per-segment badge that no export, share payload or
// history record even carried. Art. 5(1)(f) compounded it: inferring
// emotions in workplaces and schools is prohibited outright, the app
// cannot detect deployment context, and a policy line is the only control
// available for a feature that ships enabled.
//
// So this file no longer describes a subsystem. It is the **filter** that
// keeps one from existing: `CrispasrEngine` drops every tag named here at
// the parse boundary, before it can reach segment metadata, the UI, or an
// export. `test/synthetic_compliance_test.dart` pins that.
//
// Note what is *not* removed: SenseVoice remains a fully supported
// transcription backend, and its acoustic *event* tags (`SPEECH`, `BGM`,
// `LAUGHTER`, …) are still surfaced. Classifying laughter as an audio
// event describes the recording, not the speaker's inner state, and is not
// an inference about a natural person.

/// The emotion labels CrisperWeaver discards on sight.
///
/// Adding a tag here removes it from the app. Adding one to a model's
/// vocabulary *without* adding it here re-creates the Annex III 1(c)
/// exposure — which is why the compliance suite pins this set against the
/// SenseVoice label list rather than trusting it to stay in step.
class EmotionInference {
  EmotionInference._();

  /// SenseVoice emotion labels. Inferences about a person's emotional
  /// state drawn from their voice — Art. 3(39) biometric data.
  ///
  /// `EMO_UNKNOWN` is included because the system still ran the inference
  /// and reported a result, even where the result is "no determination".
  static const Set<String> tags = {
    'HAPPY',
    'SAD',
    'ANGRY',
    'NEUTRAL',
    'EMO_UNKNOWN',
    'SURPRISED',
    'FEARFUL',
    'DISGUSTED',
  };

  /// Whether [tag] is an emotion inference and must therefore be dropped.
  ///
  /// Case-insensitive: backends emit `<|HAPPY|>` and `<|Happy|>`
  /// interchangeably, and a case-sensitive check would let one of them
  /// through.
  static bool isEmotionTag(String tag) => tags.contains(tag.toUpperCase());
}
