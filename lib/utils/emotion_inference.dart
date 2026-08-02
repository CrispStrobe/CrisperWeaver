// EU AI Act Art. 50(3) — emotion recognition from voice.
//
// SenseVoice emits inline tags (`<|HAPPY|>`, `<|ANGRY|>`, …) alongside the
// transcript. Parsing those into a labelled per-segment badge means the app
// infers the emotional state of a natural person from their voice, and voice
// is biometric data — so this is an *emotion recognition system* within
// Art. 3(39), not an incidental model artefact.
//
// `docs/AI_ACT_RISK.md` asserted the opposite until the 2026-08-02 audit:
// §3.3 read "no emotion recognition is performed", which was true only of
// the Chatterbox `[angry]` prosody tags on the *generation* side. The
// recognition side had been shipping since the SenseVoice backend landed.
//
// Three duties attach, and they are not the same duty:
//
//   - Art. 50(3) binds the **deployer** — whoever runs the app over a
//     recording must inform the people in it. CrisperWeaver cannot do that
//     for them; what it can do is make the inference visible and say so,
//     which is what [disclosure] is for.
//   - Art. 5(1)(f) **prohibits** inferring emotions in the workplace and in
//     education institutions outright, and has done since 2 Feb 2025. That
//     is not a consent question — consent does not cure it. See
//     [prohibitedContextWarning].
//   - Annex III 1(c) lists emotion recognition as high-risk from
//     2 Dec 2027, which is what re-opens the Art. 49(2) registration
//     question in `AI_ACT_RISK.md` §7.3.
//
// Pure Dart so the engine, the widgets, the CLI and the compliance suite
// share one definition of "this is an emotion inference" — the tag set used
// to live as a private helper inside `crispasr_engine.dart`, where nothing
// else could see it and no test could pin it.

/// The emotion-recognition limb of the app: which model tags count as an
/// inference about a natural person, and what has to be said about them.
class EmotionInference {
  EmotionInference._();

  /// SenseVoice emotion labels. These are inferences about a person's
  /// emotional state drawn from their voice — Art. 3(39) biometric data.
  ///
  /// Deliberately excludes the *event* tags (`SPEECH`, `BGM`, `LAUGHTER`,
  /// `APPLAUSE`, …): those describe the audio, not the speaker's inner
  /// state, and classifying laughter as an acoustic event is not an
  /// emotion inference. `EMO_UNKNOWN` is included because the system still
  /// ran the inference and reported a result, even if the result is "no
  /// determination".
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

  /// Whether [tag] is an emotion inference. Case-insensitive: SenseVoice
  /// emits mixed case across backends (`<|HAPPY|>` vs `<|Happy|>`).
  static bool isEmotionTag(String tag) => tags.contains(tag.toUpperCase());

  /// Art. 50(3) disclosure, shown wherever emotion inferences are
  /// displayed.
  ///
  /// Says three things on purpose: that it is an inference rather than an
  /// observation, that the duty to tell the recorded people falls on the
  /// user, and that the workplace/education use is prohibited outright.
  /// A recipient who reads only the first clause still learns the thing
  /// that matters most — the badge is a guess.
  static const String disclosure =
      'Emotion labels are inferred by an AI model from voice characteristics. '
      'They are probabilistic guesses, not observations, and are frequently '
      'wrong. Under the EU AI Act (Art. 50(3)) you must inform the people in '
      'a recording that emotion recognition is being applied to them. '
      'Inferring emotions in the workplace or in education is prohibited '
      'outright (Art. 5(1)(f)).';

  /// The Art. 5(1)(f) limb on its own, for surfaces too narrow for the
  /// full [disclosure] — tooltips, CLI stderr, the acceptable-use policy.
  static const String prohibitedContextWarning =
      'Inferring emotions of natural persons in the workplace or in education '
      'institutions is prohibited under EU AI Act Art. 5(1)(f).';
}
