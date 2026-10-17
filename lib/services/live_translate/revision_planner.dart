// Two speeds: a fast translation now, a better one a few seconds later.
//
// Mirrors upstream's `--translate-revise` (CrispASR docs/streaming.md, "Two
// speeds"): the fast translator works sentence by sentence; a slow one — a
// translation LLM — re-translates whole paragraphs, so each sentence is
// translated with its neighbours as context, and its result replaces the
// fast translations of those sentences. A paragraph closes when its
// utterance ends or after four sentences of continuous speech. The slow pass
// only starts while the fast translator has nothing waiting, and if more
// than three paragraphs queue up the oldest is dropped: it may lag, never
// pile up.
//
// Pure bookkeeping (no isolates, no clock), so the policy is unit-tested;
// LiveTranslateController owns the slow translator and applies results.

/// One sentence as the planner sees it.
class RevisionSentence {
  const RevisionSentence({
    required this.key,
    required this.utterance,
    required this.lang,
    required this.text,
  });
  final int key;
  final int utterance;
  final String lang;
  final String text;
}

/// Sentences of one language that go to the slow translator together.
class RevisionParagraph {
  RevisionParagraph(this.id, this.lang, this.sentences);
  final int id;
  final String lang;
  final List<RevisionSentence> sentences;

  String get text => sentences.map((s) => s.text).join(' ');
  List<int> get keys => [for (final s in sentences) s.key];
}

class RevisionPlanner {
  RevisionPlanner({this.maxSentences = 4, this.maxBacklog = 3});

  final int maxSentences;
  final int maxBacklog;

  final List<RevisionSentence> _open = [];
  final List<RevisionParagraph> _queue = [];
  int _nextId = 0;

  /// Paragraphs dropped because the slow pass fell behind.
  int skipped = 0;

  /// Paragraphs waiting for the slow translator, oldest first.
  List<RevisionParagraph> get queued => List.unmodifiable(_queue);

  /// A sentence was committed. Starts a new paragraph when the utterance or
  /// the language changes; closes one at [maxSentences].
  void add(RevisionSentence s) {
    if (_open.isNotEmpty &&
        (_open.last.utterance != s.utterance || _open.last.lang != s.lang)) {
      _close();
    }
    _open.add(s);
    if (_open.length >= maxSentences) _close();
  }

  /// The utterance [utterance] ended: its paragraph is complete.
  void utteranceEnded(int utterance) {
    if (_open.isNotEmpty && _open.last.utterance == utterance) _close();
  }

  /// The session is stopping: whatever is open is a paragraph.
  void flush() {
    if (_open.isNotEmpty) _close();
  }

  /// The next paragraph to revise, when the fast translator is idle.
  RevisionParagraph? next({required bool fastIdle}) =>
      fastIdle && _queue.isNotEmpty ? _queue.removeAt(0) : null;

  void _close() {
    _queue.add(RevisionParagraph(_nextId++, _open.first.lang, List.of(_open)));
    _open.clear();
    while (_queue.length > maxBacklog) {
      _queue.removeAt(0);
      skipped++;
    }
  }
}
