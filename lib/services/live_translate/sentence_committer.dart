// Sentence-incremental commit policy for live transcribe + translate.
//
// A Dart port of CrispASR's `examples/cli/crispasr_live_translate.h`
// (`lt_committer`, merged upstream in #493, 2026-10-06). The streaming loop
// produces a growing PARTIAL hypothesis for the open utterance every step,
// and a FINAL when trailing silence closes it. Translating only finals makes
// the translation wait for a pause — tens of seconds behind on a lecture.
// Translating every partial re-translates text that is still changing and
// the output flickers.
//
// The policy sits between the two: a sentence is COMMITTED as soon as the
// recogniser has moved past it and two consecutive partials agree on it
// (LocalAgreement-2). A committed sentence is immutable — it is translated
// exactly once and never revised, not even by the final. Only the still-open
// tail after the last committed sentence may be re-translated as a draft.
//
// Everything here is pure (no I/O, no model, no clock), so the policy is
// unit-tested in test/live_translate/sentence_committer_test.dart, which
// mirrors upstream's tests/test-live-translate.cpp case for case.
//
// Differences from the C++ original, all deliberate:
//   * Dart strings are UTF-16, so tokenisation works on runes, not bytes.
//   * Case folding uses `toLowerCase()` (all scripts) rather than the
//     ASCII + Latin-1 fold the C++ hand-rolls; the alignment key only needs
//     to be stable across partials, and a broader fold is no less stable.

/// One token of a hypothesis.
class LtWord {
  LtWord(this.raw, this.norm, {this.glue = false});

  /// Token as the recogniser wrote it, punctuation included.
  final String raw;

  /// Case-folded, edge punctuation stripped — the alignment key.
  final String norm;

  /// True: joins to the previous token without a space (CJK).
  final bool glue;

  /// Stream time (s) by which this word had NOT yet been heard: the audio
  /// position of the last partial that did not contain it.
  double notBefore = 0.0;

  /// Recogniser word timing (stream seconds), when it supplied any; -1 = none.
  double tMid = -1.0;
  double tEnd = -1.0;

  LtWord copy() => LtWord(raw, norm, glue: glue)
    ..notBefore = notBefore
    ..tMid = tMid
    ..tEnd = tEnd;
}

/// A word with its recogniser timestamps, in stream seconds.
class LtTimedWord {
  const LtTimedWord(this.text, this.t0, this.t1);
  final String text;
  final double t0;
  final double t1;
}

/// A committed piece of text.
class LtSentence {
  const LtSentence(this.id, this.text, {this.complete = true, this.tEnd = -1});
  final int id;
  final String text;

  /// Stream time (s) its last word ends at, when the recogniser gave word
  /// timestamps; -1 otherwise.
  final double tEnd;

  /// False for a piece committed without reaching a sentence end: a forced
  /// commit of an over-long run, or the unterminated remainder of an
  /// utterance. Settled TEXT, but not a translation unit on its own.
  final bool complete;

  @override
  String toString() => 'LtSentence($id, "$text"${complete ? '' : ', partial'})';
}

class LtUpdate {
  /// Newly committed, in order.
  final List<LtSentence> committed = [];

  /// Text still open after the last commit.
  String tail = '';
  bool tailChanged = false;
}

class LtCommitOptions {
  const LtCommitOptions({
    this.forceCommitWords = 30,
    this.forceKeepBack = 4,
    this.pressureCommitWords = 10,
    this.maxAlignMisses = 3,
  });

  /// A tail this long with no sentence end is force-committed at a clause
  /// boundary, so an unpunctuated recogniser cannot hold translation back.
  final int forceCommitWords;

  /// Newest words kept back from a forced commit — the next partial is most
  /// likely to revise them.
  final int forceKeepBack;

  /// [forceCommitWords] while the caller reports pressure.
  final int pressureCommitWords;

  /// Partials in a row that may fail to align before resyncing on the best
  /// available guess rather than stalling.
  final int maxAlignMisses;
}

// ---------------------------------------------------------------------------
// Tokenisation helpers
// ---------------------------------------------------------------------------

bool _isCjkTerminator(int r) => r == 0x3002 || r == 0xFF01 || r == 0xFF1F;

bool _isEdgePunct(int r) {
  if (r < 0x80) {
    return (r >= 0x21 && r <= 0x2F) ||
        (r >= 0x3A && r <= 0x40) ||
        (r >= 0x5B && r <= 0x60) ||
        (r >= 0x7B && r <= 0x7E);
  }
  if (_isCjkTerminator(r)) return true;
  // ‐‑‒–—― ‘’‚‛“”„‟ …
  if ((r >= 0x2010 && r <= 0x2015) ||
      (r >= 0x2018 && r <= 0x201F) ||
      r == 0x2026) {
    return true;
  }
  return r == 0x00AB || r == 0x00BB; // « »
}

bool _isSpace(int r) => r == 0x20 || r == 0x09 || r == 0x0A || r == 0x0D;

/// Case-folded token with edge punctuation stripped.
String ltNormalise(String raw) {
  final runes = raw.runes.toList();
  var b = 0, e = runes.length;
  while (b < e && _isEdgePunct(runes[b])) {
    b++;
  }
  while (e > b && _isEdgePunct(runes[e - 1])) {
    e--;
  }
  return String.fromCharCodes(runes.sublist(b, e)).toLowerCase();
}

/// Split recogniser text into tokens. Whitespace separates tokens; a CJK
/// sentence terminator additionally closes one, so scripts written without
/// spaces still yield sentence-sized units instead of one giant "word".
List<LtWord> ltSplitWords(String text) {
  final out = <LtWord>[];
  final cur = StringBuffer();
  var glueNext = false;
  void flush(bool closedByCjk) {
    if (cur.isEmpty) return;
    final raw = cur.toString();
    out.add(LtWord(raw, ltNormalise(raw), glue: glueNext));
    cur.clear();
    glueNext = closedByCjk;
  }

  for (final r in text.runes) {
    if (_isSpace(r)) {
      flush(false);
      glueNext = false;
      continue;
    }
    cur.writeCharCode(r);
    if (_isCjkTerminator(r)) flush(true);
  }
  flush(false);
  return out;
}

String ltJoin(List<LtWord> w, int b, int e) {
  final out = StringBuffer();
  for (var i = b; i < e && i < w.length; i++) {
    if (out.isNotEmpty && !w[i].glue) out.write(' ');
    out.write(w[i].raw);
  }
  return out.toString();
}

const _abbreviations = {
  'dr', 'prof', 'nr', 'bzw', 'ca', 'usw', 'evtl', 'ggf', 'ggfs', 'inkl', //
  'vgl', 'sog', 'st', 'mr', 'mrs', 'ms', 'vs', 'jr', 'sr', 'inc', 'ltd',
  'mio', 'mrd', 'tel', 'str', 'abs', 'bsp', 'zzgl', 'fig', 'gen', 'gov',
  'rev', 'hon', 'mt', 'etc', 'approx', 'no', 'vol', 'dipl', 'ing', 'hr',
  'fr',
};

final _allDigits = RegExp(r'^[0-9]+$');

/// Does token [i] close a sentence? Deliberately conservative about '.': a
/// false split costs translation quality (the translator sees half a
/// sentence), a missed one only costs a little latency.
bool ltEndsSentence(List<LtWord> w, int i) {
  if (i < 0 || i >= w.length) return false;
  var t = w[i].raw;
  // Closing quotes / brackets after the terminator: `sagte er."`
  const closers = {'"', "'", ')', ']', '“', '”', '»', '«'};
  while (t.isNotEmpty && closers.contains(t[t.length - 1])) {
    t = t.substring(0, t.length - 1);
  }
  if (t.isEmpty) return false;
  final last = t.runes.last;
  if (_isCjkTerminator(last)) return true;
  if (last == 0x21 || last == 0x3F) return true; // ! ?
  if (last != 0x2E) return false; // .
  // "..." / "…" is a hesitation, not an end.
  if (t.endsWith('..')) return false;
  final n = w[i].norm;
  if (n.isEmpty) return false;
  // "3." / "21." is a German ordinal or an enumeration ("am 3. Oktober").
  // A longer number is a year or a quantity and can close a sentence.
  if (_allDigits.hasMatch(n) && n.length <= 2) return false;
  // Single letter: initials, "z. B.", "u. a.", "d. h.", "e. g.".
  if (n.runes.length == 1) return false;
  // Inner dot: "z.B.", "e.g.", "U.S.".
  if (n.contains('.')) return false;
  return !_abbreviations.contains(n);
}

// ---------------------------------------------------------------------------
// The committer
// ---------------------------------------------------------------------------

/// Tracks one stream. Feed every partial and every final; get back the
/// sentences that became committed and the current open tail.
class SentenceCommitter {
  SentenceCommitter([this.opt = const LtCommitOptions()]);

  final LtCommitOptions opt;

  static const _kKeep = 96; // committed words remembered for alignment
  static const _kKey = 8; // of which this many form the match key

  int _utteranceId = -1;
  final List<String> _committed = []; // norms, current utterance, last _kKeep
  int _nCommitted = 0; // words committed in this utterance
  List<LtWord> _prevOpen = []; // previous partial's open words
  String _lastTail = '';
  String _lastText = ''; // the last partial that resolved (lined up)
  int _alignMisses = 0;
  int _alignMissesTotal = 0;
  double _decodeFrom = -1.0;
  bool _decodeFromExact = false;
  double _committedUntil = -1.0; // end time of last committed word, if timed
  double _lastPartialT = 0.0;
  int _nextId = 0;

  /// [tAudio] is the stream time (s of audio received) this partial was
  /// decoded at; it only feeds [decodeFrom]. [timed], when the recogniser has
  /// word timestamps, lists the words of this hypothesis with their times
  /// (it may cover only the END of [text]).
  LtUpdate onPartial(int utteranceId, String text,
      {double tAudio = 0.0, List<LtTimedWord>? timed}) {
    _syncUtterance(utteranceId);
    final up = LtUpdate();
    final words = ltSplitWords(text);
    var firstTimed = words.length;
    if (timed != null) {
      // Walk both lists from the end for as long as they agree.
      var i = words.length, j = timed.length;
      while (i > 0 && j > 0 && words[i - 1].norm == ltNormalise(timed[j - 1].text)) {
        words[i - 1].tMid = 0.5 * (timed[j - 1].t0 + timed[j - 1].t1);
        words[i - 1].tEnd = timed[j - 1].t1;
        i--;
        j--;
      }
      firstTimed = i;
    }
    var p = 0;
    var resumed = false;
    // The boundary by the clock: a word is open when its MIDDLE lies after
    // the boundary. Usable when the timed words reach back to the boundary.
    if (_committedUntil >= 0.0 &&
        firstTimed < words.length &&
        (firstTimed == 0 || words[firstTimed].tMid <= _committedUntil)) {
      p = firstTimed;
      while (p < words.length && words[p].tMid <= _committedUntil) {
        p++;
      }
      // A forced commit can end mid-phrase; re-decoding from just before the
      // boundary may hear its last word again, timed a little late.
      if (p < words.length &&
          _committed.isNotEmpty &&
          words[p].norm == _committed.last &&
          words[p].tMid - _committedUntil < 0.35) {
        p++;
      }
      resumed = true;
      _alignMisses = 0;
    }
    if (!resumed) {
      final rp = _resumePoint(words, isFinal: false);
      if (rp == null) {
        // Does not line up with what we committed. Committed text is
        // immutable, so wait for a partial that does — and withdraw
        // decodeFrom so the next one is decoded from the region start.
        _alignMissesTotal++;
        _lastText = '';
        _decodeFrom = -1.0;
        _decodeFromExact = false;
        _committedUntil = -1.0;
        up.tail = _lastTail;
        return up;
      }
      p = rp;
    }
    final open = words.sublist(p);

    // LocalAgreement-2: how far does this partial agree with the last one?
    var agree = 0;
    while (agree < open.length &&
        agree < _prevOpen.length &&
        open[agree].norm == _prevOpen[agree].norm) {
      agree++;
    }
    // A word keeps the bound of the word that stood at its position before.
    for (var i = 0; i < open.length; i++) {
      open[i].notBefore =
          i < _prevOpen.length ? _prevOpen[i].notBefore : _lastPartialT;
    }
    _lastPartialT = tAudio;

    // Commit through the last sentence end that the recogniser has moved
    // past AND the previous partial also wrote, terminator included.
    var cut = 0;
    for (var i = 0; i + 1 < open.length && i < agree; i++) {
      if (ltEndsSentence(open, i) && open[i].raw == _prevOpen[i].raw) {
        cut = i + 1;
      }
    }
    var done = 0;
    for (var i = 0; i < cut; i++) {
      if (ltEndsSentence(open, i)) {
        _commit(open, done, i + 1, up);
        done = i + 1;
      }
    }
    // Forced commit of an over-long unterminated run.
    final forceWords =
        pressure ? opt.pressureCommitWords : opt.forceCommitWords;
    if (open.length - done > forceWords) {
      final stableEnd =
          agree > opt.forceKeepBack ? agree - opt.forceKeepBack : 0;
      final half = forceWords ~/ 2;
      if (stableEnd > done + half) {
        var fc = stableEnd;
        for (var i = stableEnd; i > done + half; i--) {
          final r = open[i - 1].raw;
          if (r.endsWith(',') || r.endsWith(';') || r.endsWith(':')) {
            fc = i;
            break;
          }
        }
        _commit(open, done, fc, up);
        done = fc;
      }
    }
    _prevOpen = open.sublist(done);
    _lastText = text;
    up.tail = ltJoin(_prevOpen, 0, _prevOpen.length);
    up.tailChanged = up.tail != _lastTail;
    _lastTail = up.tail;
    return up;
  }

  /// The speaker paused and the last partial already covered all of it. If
  /// the open text ends on a sentence terminator, commit it now. Text that
  /// does not end a sentence stays open — a pause mid-sentence is a breath.
  LtUpdate onPause(int utteranceId) {
    final up = LtUpdate();
    if (utteranceId != _utteranceId ||
        _prevOpen.isEmpty ||
        !ltEndsSentence(_prevOpen, _prevOpen.length - 1)) {
      return up;
    }
    final open = _prevOpen;
    var done = 0;
    for (var i = 0; i < open.length; i++) {
      if (ltEndsSentence(open, i)) {
        _commit(open, done, i + 1, up);
        done = i + 1;
      }
    }
    _prevOpen = [];
    up.tailChanged = _lastTail.isNotEmpty;
    _lastTail = '';
    return up;
  }

  /// The utterance closed: commit everything still open. Sentences committed
  /// from partials stay as they are — the final only supplies the remainder.
  LtUpdate onFinal(int utteranceId, String text) {
    _syncUtterance(utteranceId);
    final up = LtUpdate();
    void commitAll(List<LtWord> open) {
      var done = 0;
      for (var i = 0; i < open.length; i++) {
        if (ltEndsSentence(open, i)) {
          _commit(open, done, i + 1, up);
          done = i + 1;
        }
      }
      if (done < open.length) _commit(open, done, open.length, up);
      up.tailChanged = _lastTail.isNotEmpty;
      _resetUtterance();
    }

    // The final is the very hypothesis we resolved last: what is open is
    // already known, without needing the committed words in view.
    if (_lastText.isNotEmpty && text == _lastText) {
      commitAll(_prevOpen);
      return up;
    }
    final words = ltSplitWords(text);
    final rp = _resumePoint(words, isFinal: true);
    if (rp == null) {
      // No later hypothesis to wait for: commit what the last hypothesis
      // that DID line up left open, rather than guess at this one.
      commitAll(_prevOpen);
      return up;
    }
    commitAll(words.sublist(rp));
    return up;
  }

  int get sentencesCommitted => _nextId;

  /// Stream time (s) from which the open utterance still needs decoding, or
  /// < 0 for "from its start". An ESTIMATE from when each word first showed
  /// up, deliberately early; decode from a couple of seconds before it so the
  /// end of the committed text is in view to line up against.
  double get decodeFrom => _decodeFrom;

  /// True when [decodeFrom] is a recogniser word timestamp rather than the
  /// estimate; the caller can then start a fraction of a second before it.
  bool get decodeFromExact => _decodeFrom >= 0.0 && _decodeFromExact;

  /// The caller is re-decoding more open audio per step than it can afford.
  /// While set, an unterminated run is force-committed much earlier.
  bool pressure = false;

  /// Partials that did not line up with the committed text.
  int get alignMisses => _alignMissesTotal;

  void _syncUtterance(int id) {
    if (id != _utteranceId) {
      _resetUtterance();
      _utteranceId = id;
    }
  }

  void _resetUtterance() {
    _committed.clear();
    _prevOpen = [];
    _lastTail = '';
    _lastText = '';
    _nCommitted = 0;
    _alignMisses = 0;
    _decodeFrom = -1.0;
    _decodeFromExact = false;
    _committedUntil = -1.0;
    _lastPartialT = 0.0;
  }

  void _commit(List<LtWord> w, int b, int e, LtUpdate up) {
    if (e <= b) return;
    up.committed.add(LtSentence(_nextId++, ltJoin(w, b, e),
        complete: ltEndsSentence(w, e - 1), tEnd: w[e - 1].tEnd));
    for (var i = b; i < e; i++) {
      _committed.add(w[i].norm);
    }
    _nCommitted += e - b;
    // Half a second of slack: a recogniser can hold a word back until it has
    // heard a little of what follows.
    _decodeFrom = w[e - 1].notBefore - 0.5;
    _committedUntil = w[e - 1].tEnd;
    _decodeFromExact = _committedUntil >= 0.0;
    if (_decodeFromExact) _decodeFrom = _committedUntil;
    if (_committed.length > _kKeep) {
      _committed.removeRange(0, _committed.length - _kKeep);
    }
  }

  /// Index in [words] where not-yet-committed text begins, or null when the
  /// hypothesis does not line up (yet).
  ///
  /// Overlap alignment of the last few committed words (the key) against the
  /// hypothesis: the key may start before the hypothesis does (the window
  /// evicted it — free), must end inside it, and may differ by substitutions
  /// and gaps (-1 each; a match is +2). A position-by-position compare would
  /// break on re-renderings like "12%" → "zwölf Prozent".
  int? _resumePoint(List<LtWord> words, {required bool isFinal}) {
    if (_committed.isEmpty) return 0;
    final m = _committed.length < _kKey ? _committed.length : _kKey;
    final n = words.length;
    final key = _committed.sublist(_committed.length - m);
    var prev = List<int>.filled(n + 1, 0);
    var cur = List<int>.filled(n + 1, 0);
    for (var i = 1; i <= m; i++) {
      cur[0] = 0; // key prefix cut off by the window start
      for (var j = 1; j <= n; j++) {
        final diag = prev[j - 1] + (key[i - 1] == words[j - 1].norm ? 2 : -1);
        final upS = prev[j] - 1; // key word missing from the hypothesis
        final left = cur[j - 1] - 1; // extra word in the hypothesis
        cur[j] = diag > upS ? (diag > left ? diag : left) : (upS > left ? upS : left);
      }
      final t = prev;
      prev = cur;
      cur = t;
    }
    var bestP = 0;
    var bestScore = 0;
    var bestDist = 1 << 30;
    for (var p = 1; p <= n; p++) {
      final dist = (p - _nCommitted).abs();
      if (prev[p] > bestScore ||
          (prev[p] == bestScore && bestScore > 0 && dist < bestDist)) {
        bestScore = prev[p];
        bestP = p;
        bestDist = dist;
      }
    }
    // Three net matching words when the key is long enough; every word when
    // it is not.
    final need = m >= 4 ? 5 : 2 * m;
    if (bestScore >= need) {
      _alignMisses = 0;
      return bestP;
    }
    if (isFinal) return null;
    if (++_alignMisses < opt.maxAlignMisses) return null;
    // Resync on the best guess. No overlap at all means the committed text
    // has left the recogniser's window, so everything here is new.
    _alignMisses = 0;
    return bestScore > 0 ? bestP : 0;
  }
}

/// Collects committed pieces into translation units.
///
/// A forced commit (under pressure, or of a very long unpunctuated run) is
/// settled TEXT but not a translation unit: translated cold, half a sentence
/// comes out as nonsense ("…due to strong exports." / "Caused by France and
/// Italy."). Upstream's sink holds such pieces and translates them together
/// with the rest of their sentence; this does the same.
class SentenceAssembler {
  final List<LtSentence> _held = [];

  /// Text held back so far (shown as settled source text, untranslated).
  String get heldText => _held.map((s) => s.text).join(' ');
  bool get hasHeld => _held.isNotEmpty;

  /// Feed newly committed pieces. Returns the complete translation units
  /// they finish, as `(firstPieceId, text, tEnd)` — tEnd as [LtSentence.tEnd]
  /// of the unit's last piece.
  List<(int, String, double)> add(List<LtSentence> pieces) {
    final out = <(int, String, double)>[];
    for (final s in pieces) {
      _held.add(s);
      if (s.complete) out.add(_drain()!);
    }
    return out;
  }

  /// The utterance ended: whatever is held is a unit on its own now.
  (int, String, double)? flush() => _held.isEmpty ? null : _drain();

  (int, String, double)? _drain() {
    if (_held.isEmpty) return null;
    final unit = (_held.first.id, heldText, _held.last.tEnd);
    _held.clear();
    return unit;
  }
}
