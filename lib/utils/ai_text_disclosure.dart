// EU AI Act Art. 50(2) — disclosure for AI-*generated text*.
//
// Art. 50(2) reaches synthetic text, not just audio. The audio path is
// marked three ways (spread-spectrum watermark, C2PA manifest, container
// metadata); text has no container to carry a manifest, so the marking is
// the disclosure line itself plus, on the HTTP surface, the
// `x-content-ai-generated` header the audio endpoints already set.
//
// [OcrResult.disclosure] established the shape for OCR output. This is the
// same contract for the LLM-backed text features — summarisation,
// translation — which generate or substantially restate content rather
// than merely transcribing it.
//
// Deliberately NOT covered: rule-based transcript cleanup (filler removal,
// sentence casing, punctuation, whitespace). Art. 50(2) exempts systems
// that "perform an assistive function for standard editing" and do not
// substantially alter the input or its semantics — which is exactly what
// those toggles do. Summaries and translations are not that.
//
// Kept pure-Dart and separate from the widgets so the CLI, the HTTP
// server, and the compliance test suite can all reach the same strings.

/// Art. 50(2) disclosure strings for AI-generated text, plus the helper
/// that attaches one when the text leaves the app.
class AiTextDisclosure {
  AiTextDisclosure._();

  /// LLM-generated meeting summaries — action items, key topics, decisions.
  /// The model infers structure that was never stated verbatim, so the
  /// "verify before relying on it" warning carries more weight here than
  /// it does for transcription.
  static const String summary =
      'AI-generated: summarised by a language model from a transcript. '
      'It may omit, merge, or misattribute content. Verify before relying '
      'on it.';

  /// Machine-translated text. Distinct wording from [summary] because the
  /// failure mode differs: translation preserves the content and distorts
  /// the meaning, rather than dropping content outright.
  static const String translation =
      'AI-generated: machine-translated by an on-device model. Meaning may '
      'shift in translation. Verify before relying on it.';

  /// [text] prefixed with [disclosure], matching the bracketed shape
  /// `OcrResult.textWithDisclosure` uses so the two look alike wherever
  /// they land side by side.
  ///
  /// Empty in, empty out — there is nothing to disclose about no text, and
  /// a bare disclosure on an empty clipboard is noise.
  static String attach(String text, String disclosure) =>
      text.trim().isEmpty ? '' : '[$disclosure]\n\n$text';

  /// [attach] with the [summary] wording.
  static String forSummary(String text) => attach(text, summary);

  /// [attach] with the [translation] wording.
  static String forTranslation(String text) => attach(text, translation);
}
