// EU AI Act — the audio-Q&A prompts this app refuses to run.
//
// `CrispasrEngine.transcribe(askPrompt: …)` hands a free-text question to
// an instruct-tuned audio LLM (voxtral, qwen3-asr), which answers it from
// the audio instead of transcribing. That is a general capability and a
// legitimate one — "summarise this", "what was decided" — but it is also a
// route to emotion recognition that no output filter can close.
//
// `EmotionInference` works because SenseVoice emits a closed set of
// `<|HAPPY|>` literals at a single parse boundary. An LLM answering "the
// speaker sounds frustrated" is free prose: there is no tag to discard, no
// vocabulary to enumerate, and no boundary at which the inference is
// distinguishable from any other sentence. Output-side control is not
// available here, so the control moves to the input.
//
// **Why refuse rather than warn or disclose.** Art. 50(3) transparency is
// the wrong instrument: it binds deployers and presumes the system may
// lawfully run. Inferring emotions is *prohibited outright* in workplaces
// and educational institutions (Art. 5(1)(f)), the app cannot detect its
// deployment context, and a prohibition is not something a user can consent
// their way past. Outside those contexts, an emotion recognition system is
// Annex III 1(c) high-risk from 2 Dec 2027 — the obligation the badge in
// `AI_ACT_RISK.md` §2.8 was deleted to avoid. Running the prompt and
// labelling the answer would re-acquire exactly that obligation.
//
// **What this does not claim.** The list below is a keyword filter over a
// free-text field, and a determined user can defeat it by rephrasing
// ("describe the prosody", "is the speaker being sincere"). It is a control
// against the app *affording* emotion inference — which is what supplies the
// "intended purpose" in Art. 3(39) — not a guarantee that no model ever
// emits an affective sentence. That limit is stated here rather than
// discovered later, and it is the same honest posture as the discard list in
// `EmotionInference`: the control only works for the terms it names.
//
// Kept pure-Dart and dependency-free so the engine, the HTTP server, the CLI
// and the compliance suite all enforce one list.

/// Guards the audio-Q&A prompt against requests for emotional, affective, or
/// intent-bearing attributes of a speaker.
class AffectivePromptGuard {
  AffectivePromptGuard._();

  /// Latin-script terms, matched on word boundaries so `sad` does not fire
  /// on `sadly cut off` — sorry, on `saddle`. Case-insensitive.
  ///
  /// Deliberately **not** included: bare `sound`, `voice`, `feel`. Each
  /// carries an overwhelmingly non-affective reading in this context
  /// ("what does the recording sound like", "whose voice is this") and
  /// including them would refuse ordinary transcription work while adding
  /// nothing a rephrase could not bypass anyway.
  static const List<String> wordTerms = [
    // Affective state, named directly.
    'emotion', 'emotions', 'emotional', 'emotionally',
    'mood', 'moods', 'moody',
    'sentiment', 'affective',
    'feeling', 'feelings',
    'temperament', 'demeanour', 'demeanor',
    // Prosody used as a proxy for state.
    'tone', 'intonation', 'prosody',
    // Discrete emotion labels.
    'happy', 'happiness', 'sad', 'sadness', 'angry', 'anger', 'furious',
    'upset', 'frustrated', 'frustration', 'annoyed', 'irritated',
    'anxious', 'anxiety', 'nervous', 'nervousness', 'stressed', 'stress',
    'afraid', 'fearful', 'scared', 'disgusted', 'surprised', 'excited',
    'depressed', 'calm', 'agitated',
    // Intent / veracity — Art. 3(39) reaches intentions, not just emotions.
    'intent', 'intention', 'intentions',
    'sincere', 'sincerity', 'insincere',
    'honest', 'dishonest', 'lying', 'deceptive', 'truthful',
    'attitude',
    // German.
    'emotionen', 'gefuehl', 'gefuehle', 'gefühl', 'gefühle',
    'stimmung', 'stimmungen', 'tonfall', 'laune', 'gemuetszustand',
    'gemütszustand', 'absicht', 'absichten',
    'wuetend', 'wütend', 'traurig', 'gluecklich', 'glücklich',
    'veraergert', 'verärgert', 'nervoes', 'nervös', 'gestresst',
    'aengstlich', 'ängstlich', 'ehrlich', 'unehrlich', 'luegt', 'lügt',
    'aufgeregt', 'genervt',
  ];

  /// CJK terms, matched as substrings — Chinese has no word boundaries for
  /// `\b` to anchor to.
  static const List<String> substringTerms = [
    '情绪', '情感', '语气', '心情', '感受', '情感状态',
    '生气', '愤怒', '悲伤', '难过', '高兴', '开心', '快乐',
    '紧张', '焦虑', '害怕', '恐惧', '惊讶', '厌恶', '沮丧',
    '意图', '动机', '说谎', '撒谎', '诚实', '真诚', '态度',
  ];

  static final RegExp _wordPattern = RegExp(
    r'(?<![\p{L}\p{N}])(' +
        wordTerms.map(RegExp.escape).join('|') +
        r')(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  /// The term in [prompt] that trips the guard, or null when it is clean.
  ///
  /// Returned rather than a bare bool so the refusal can name what it
  /// objected to — a refusal the user cannot diagnose is a bug report.
  static String? offendingTerm(String? prompt) {
    if (prompt == null) return null;
    final text = prompt.trim();
    if (text.isEmpty) return null;
    final m = _wordPattern.firstMatch(text);
    if (m != null) return m.group(1);
    for (final term in substringTerms) {
      if (text.contains(term)) return term;
    }
    return null;
  }

  /// Whether [prompt] asks for an affective or intent-bearing attribute of
  /// a speaker and must therefore be refused.
  static bool isAffective(String? prompt) => offendingTerm(prompt) != null;

  /// Plain-language refusal, naming [term] so the user can rephrase.
  ///
  /// Used verbatim by the CLI and the HTTP server; the GUI shows the
  /// localised `askPromptRefusedAffective` string instead and keeps this as
  /// the log line.
  static String refusalMessage(String term) =>
      'Refusing this audio Q&A prompt: it asks the model to infer an '
      'emotional, affective, or intent-bearing attribute of a speaker '
      '(matched "$term"). Inferring emotions from voice is an emotion '
      'recognition system under EU AI Act Art. 3(39) — prohibited outright '
      'in workplaces and educational institutions (Art. 5(1)(f)) and '
      'high-risk under Annex III 1(c) elsewhere. CrisperWeaver does not '
      'perform emotion recognition. Ask about what was said rather than how '
      'the speaker sounded.';
}
