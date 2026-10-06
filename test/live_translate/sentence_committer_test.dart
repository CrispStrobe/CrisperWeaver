// Mirrors CrispASR tests/test-live-translate.cpp (#493) case for case, so a
// behaviour change upstream can be diffed against this port.
import 'package:crisper_weaver/services/live_translate/sentence_committer.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> texts(LtUpdate u) => u.committed.map((s) => s.text).toList();

bool ends(String text, int i) => ltEndsSentence(ltSplitWords(text), i);

void main() {
  test('tokens normalise case and edge punctuation', () {
    final w = ltSplitWords('  „Guten Morgen!“  Ärger, ja. ');
    expect(w.length, 4);
    expect(w[0].raw, '„Guten');
    expect(w[0].norm, 'guten');
    expect(w[1].norm, 'morgen');
    expect(w[2].norm, 'ärger');
    expect(w[3].norm, 'ja');
  });

  test('sentence ends — German ordinals and abbreviations are not ends', () {
    expect(ends('Das ist gut.', 2), isTrue);
    expect(ends('Wirklich?', 0), isTrue);
    expect(ends('Er sagte: "Nein!"', 2), isTrue);
    expect(ends('am 3. Oktober', 1), isFalse);
    expect(ends('z. B. hier', 0), isFalse);
    expect(ends('z. B. hier', 1), isFalse);
    expect(ends('Herr Dr. Meier', 1), isFalse);
    expect(ends('z.B. hier', 0), isFalse);
    expect(ends('Moment...', 0), isFalse);
    expect(ends('im Jahr 1990.', 2), isTrue);
    expect(ends('kein Ende', 1), isFalse);
  });

  test('a script without spaces still yields sentence units', () {
    final w = ltSplitWords('今日は晴れです。明日は雨です。');
    expect(w.length, 2);
    expect(ltEndsSentence(w, 0), isTrue);
    expect(ltJoin(w, 0, 2), '今日は晴れです。明日は雨です。');
  });

  test('a sentence commits once its terminator survives new right-context',
      () {
    final c = SentenceCommitter();
    expect(c.onPartial(1, 'Guten Morgen.').committed, isEmpty);
    expect(c.onPartial(1, 'Guten Morgen zusammen.').committed, isEmpty);
    final u = c.onPartial(1, 'Guten Morgen zusammen. Ich');
    expect(texts(u), ['Guten Morgen zusammen.']);
    expect(u.tail, 'Ich');
    expect(u.committed[0].id, 0);
  });

  test('a sentence first seen WITH right-context waits for a second partial',
      () {
    final c = SentenceCommitter();
    c.onPartial(1, 'Guten');
    expect(c.onPartial(1, 'Guten Morgen zusammen. Ich').committed, isEmpty);
    expect(texts(c.onPartial(1, 'Guten Morgen zusammen. Ich bin')),
        ['Guten Morgen zusammen.']);
  });

  test('the cut-end period of a partial does not split a sentence', () {
    final c = SentenceCommitter();
    c.onPartial(1, 'Ich gehe.');
    expect(c.onPartial(1, 'Ich gehe nach').committed, isEmpty);
    expect(c.onPartial(1, 'Ich gehe nach Hause.').committed, isEmpty);
    expect(texts(c.onPartial(1, 'Ich gehe nach Hause. Dann')),
        ['Ich gehe nach Hause.']);
  });

  test('committed text never comes out twice', () {
    final c = SentenceCommitter();
    c.onPartial(1, 'Erster Satz. Zweiter');
    expect(texts(c.onPartial(1, 'Erster Satz. Zweiter Satz')), ['Erster Satz.']);
    expect(c.onPartial(1, 'Erster Satz. Zweiter Satz').committed, isEmpty);
    expect(
        c.onPartial(1, 'Erster Satz. Zweiter Satz ist hier. Dritter').committed,
        isEmpty);
    expect(
        texts(c.onPartial(
            1, 'Erster Satz. Zweiter Satz ist hier. Dritter Satz')),
        ['Zweiter Satz ist hier.']);
    final f =
        c.onFinal(1, 'Erster Satz. Zweiter Satz ist hier. Dritter Satz kommt.');
    expect(texts(f), ['Dritter Satz kommt.']);
    expect(f.committed[0].id, 2);
  });

  test('the final commits everything when no partial did', () {
    final c = SentenceCommitter();
    c.onPartial(7, 'Hallo');
    final f = c.onFinal(7, 'Hallo zusammen. Wie geht es euch? Gut');
    expect(texts(f), ['Hallo zusammen.', 'Wie geht es euch?', 'Gut']);
    expect(texts(c.onFinal(8, 'Neu.')), ['Neu.']);
  });

  test('alignment survives the rolling window evicting the start', () {
    final c = SentenceCommitter();
    c.onPartial(1, 'Wir beginnen jetzt mit dem ersten Teil. Danach');
    expect(
        texts(c.onPartial(
            1, 'Wir beginnen jetzt mit dem ersten Teil. Danach kommt')),
        ['Wir beginnen jetzt mit dem ersten Teil.']);
    c.onPartial(1, 'mit dem ersten Teil. Danach kommt der zweite Teil. Und');
    final u = c.onPartial(
        1, 'mit dem ersten Teil. Danach kommt der zweite Teil. Und dann');
    expect(texts(u), ['Danach kommt der zweite Teil.']);
    expect(u.tail, 'Und dann');
  });

  test('a re-rendered number inside committed text does not re-commit', () {
    final c = SentenceCommitter();
    c.onPartial(1,
        'Die Umsätze sind im Vergleich zum Vorjahr um 12% gestiegen. Das ist');
    expect(
        texts(c.onPartial(1,
            'Die Umsätze sind im Vergleich zum Vorjahr um 12% gestiegen. Das ist vor')),
        ['Die Umsätze sind im Vergleich zum Vorjahr um 12% gestiegen.']);
    var u = c.onPartial(1,
        'Die Umsätze sind im Vergleich zum Vorjahr um zwölf Prozent gestiegen. Das ist vor allem');
    expect(u.committed, isEmpty);
    expect(u.tail, 'Das ist vor allem');
    u = c.onFinal(1,
        'Die Umsätze sind im Vergleich zum Vorjahr um zwölf Prozent gestiegen. Das ist vor allem so.');
    expect(texts(u), ['Das ist vor allem so.']);
  });

  test('a revised boundary stalls instead of duplicating, then resyncs', () {
    final c = SentenceCommitter();
    c.onPartial(1, 'Alpha beta gamma delta. Epsilon');
    expect(c.onPartial(1, 'Alpha beta gamma delta. Epsilon zeta').committed,
        hasLength(1));
    var u = c.onPartial(1, 'Omega psi chi phi tau');
    expect(u.committed, isEmpty);
    expect(u.tail, 'Epsilon zeta');
    c.onPartial(1, 'Omega psi chi phi tau sigma');
    u = c.onPartial(1, 'Omega psi chi phi tau sigma rho');
    expect(u.tail, 'Omega psi chi phi tau sigma rho');
  });

  test('unpunctuated speech is force-committed at a stable point', () {
    final c = SentenceCommitter();
    final text = StringBuffer();
    late LtUpdate u;
    var committedWords = 0;
    for (var i = 0; i < 60; i++) {
      text.write(i == 0 ? 'w$i' : ' w$i');
      u = c.onPartial(1, text.toString());
      for (final s in u.committed) {
        committedWords += ltSplitWords(s.text).length;
      }
    }
    expect(committedWords, greaterThan(0));
    expect(ltSplitWords(u.tail).length, lessThanOrEqualTo(31));
    expect(committedWords + ltSplitWords(u.tail).length, 60);
  });

  test('under pressure a long open sentence is committed at a clause boundary',
      () {
    const a =
        'eins zwei drei vier fünf sechs, sieben acht neun zehn elf zwölf dreizehn vierzehn fünfzehn';
    {
      final c = SentenceCommitter();
      c.onPartial(1, a);
      expect(c.onPartial(1, '$a sechzehn').committed, isEmpty);
    }
    final c = SentenceCommitter()..pressure = true;
    c.onPartial(1, a, tAudio: 5.0);
    final u = c.onPartial(1, '$a sechzehn', tAudio: 5.5);
    expect(texts(u), ['eins zwei drei vier fünf sechs,']);
    expect(u.tail,
        'sieben acht neun zehn elf zwölf dreizehn vierzehn fünfzehn sechzehn');
    expect(u.committed.single.complete, isFalse);
  });

  test('decodeFrom moves with commits and is withdrawn on a miss', () {
    final c = SentenceCommitter();
    expect(c.decodeFrom, lessThan(0));
    c.onPartial(1, 'Erster Satz.', tAudio: 4.0);
    c.onPartial(1, 'Erster Satz. Zweiter', tAudio: 4.5);
    expect(c.decodeFrom, lessThanOrEqualTo(4.0));
    expect(c.decodeFrom, greaterThanOrEqualTo(-0.5));
    c.onPartial(1, 'Erster Satz. Zweiter Satz hier. Dritter', tAudio: 6.0);
    c.onPartial(1, 'Erster Satz. Zweiter Satz hier. Dritter Satz', tAudio: 6.5);
    final from = c.decodeFrom;
    expect(from, greaterThan(3.5));
    expect(from, lessThanOrEqualTo(6.0));
    c.onPartial(1, 'Ganz anderer Text ohne Bezug', tAudio: 7.0);
    expect(c.decodeFrom, lessThan(0));
    expect(c.alignMisses, 1);
  });

  test('a pause commits a finished sentence, and only a finished one', () {
    final c = SentenceCommitter();
    c.onPartial(1, 'Haben Sie Fragen');
    expect(c.onPause(1).committed, isEmpty);
    c.onPartial(1, 'Haben Sie Fragen?');
    expect(texts(c.onPause(1)), ['Haben Sie Fragen?']);
    expect(c.onPause(1).committed, isEmpty);
    expect(c.onPartial(1, 'Haben Sie Fragen? Gut').committed, isEmpty);
    expect(texts(c.onFinal(1, 'Haben Sie Fragen? Gut.')), ['Gut.']);
    c.onPartial(2, 'Ende.');
    expect(c.onPause(3).committed, isEmpty);
  });

  test('with word timestamps the boundary is a time, not an alignment', () {
    final c = SentenceCommitter();
    const t1 = [
      LtTimedWord('Erster', 0.2, 0.6),
      LtTimedWord('Satz.', 0.6, 1.0),
      LtTimedWord('Zweiter', 1.4, 1.9),
    ];
    c.onPartial(1, 'Erster Satz.', tAudio: 1.1);
    expect(texts(c.onPartial(1, 'Erster Satz. Zweiter', tAudio: 2.0, timed: t1)),
        ['Erster Satz.']);
    expect(c.decodeFromExact, isTrue);
    expect(c.decodeFrom, 1.0);
    const t2 = [
      LtTimedWord('atz.', 0.8, 1.0),
      LtTimedWord('Zweiter', 1.4, 1.9),
      LtTimedWord('Satz', 1.9, 2.3),
      LtTimedWord('hier.', 2.3, 2.7),
      LtTimedWord('Und', 3.0, 3.2),
    ];
    var u =
        c.onPartial(1, 'atz. Zweiter Satz hier. Und', tAudio: 3.3, timed: t2);
    expect(c.alignMisses, 0);
    expect(u.committed, isEmpty);
    expect(u.tail, 'Zweiter Satz hier. Und');
    final t3 = [...t2, const LtTimedWord('dann', 3.2, 3.5)];
    u = c.onPartial(1, 'atz. Zweiter Satz hier. Und dann',
        tAudio: 3.6, timed: t3);
    expect(texts(u), ['Zweiter Satz hier.']);
    expect(u.committed.single.tEnd, 2.7,
        reason: 'a committed sentence carries its last word\'s end time');
    expect(c.decodeFrom, 2.7);
    const t4 = [LtTimedWord('Ende', 6.0, 6.4), LtTimedWord('gut.', 6.4, 6.8)];
    u = c.onPartial(1, 'Ende gut.', tAudio: 7.0, timed: t4);
    expect(c.alignMisses, 0);
    expect(u.tail, 'Ende gut.');
    {
      final d = SentenceCommitter();
      const a = [LtTimedWord('Eins.', 0.1, 0.5), LtTimedWord('Zwei', 0.9, 1.2)];
      d.onPartial(1, 'Eins.', tAudio: 0.6);
      d.onPartial(1, 'Eins. Zwei', tAudio: 1.3, timed: a);
      const b = [LtTimedWord('Zwei', 0.9, 1.2), LtTimedWord('drei.', 1.2, 1.6)];
      d.onPartial(1, 'Zwei drei.', tAudio: 1.8, timed: b);
      expect(texts(d.onFinal(1, 'Zwei drei.')), ['Zwei drei.']);
    }
    {
      final d = SentenceCommitter()..pressure = true;
      final a = <LtTimedWord>[];
      final text = StringBuffer();
      for (var i = 0; i < 16; i++) {
        final w = i == 6 ? 'den' : 'w$i';
        a.add(LtTimedWord(w, 0.3 * i, 0.3 * i + 0.3));
        text.write(i == 0 ? w : ' $w');
        d.onPartial(1, text.toString(), tAudio: 0.3 * i + 0.4, timed: a);
      }
      expect(d.decodeFromExact, isTrue);
      final boundary = d.decodeFrom;
      final k = (boundary / 0.3 + 0.5).toInt() - 1;
      final b = [LtTimedWord(a[k].text, boundary - 0.1, boundary + 0.2)];
      final t2b = StringBuffer(a[k].text);
      for (var i = k + 1; i < a.length; i++) {
        b.add(a[i]);
        t2b.write(' ${a[i].text}');
      }
      final u2 = d.onPartial(1, t2b.toString(), tAudio: 6.0, timed: b);
      expect(ltSplitWords(u2.tail).first.raw, a[k + 1].text);
    }
    const bad = [LtTimedWord('ganz', 5.0, 5.2), LtTimedWord('anders', 5.2, 5.5)];
    u = c.onPartial(1, 'Zweiter Satz hier. Und dann weiter',
        tAudio: 8.0, timed: bad);
    expect(u.tail, 'Und dann weiter');
  });

  test('a final that does not line up still commits what was open', () {
    final c = SentenceCommitter();
    c.onPartial(1, 'Er hat dort gearbeitet. Haben Sie');
    expect(c.onPartial(1, 'Er hat dort gearbeitet. Haben Sie Fragen?').committed,
        hasLength(1));
    expect(c.onPartial(1, 'völlig anderer unpassender Text hier').committed,
        isEmpty);
    final f = c.onFinal(1, 'völlig anderer unpassender Text hier');
    expect(texts(f), ['Haben Sie Fragen?']);
  });

  group('SentenceAssembler', () {
    test('a forced clause split is not translated cold', () {
      final c = SentenceCommitter(const LtCommitOptions(pressureCommitWords: 6))
        ..pressure = true;
      final asm = SentenceAssembler();
      const a =
          'das ist vor allem auf den starken Export nach Frankreich und Italien';
      final units = <String>[];
      units.addAll(asm.add(c.onPartial(1, a, tAudio: 1.0).committed).map((u) => u.$2));
      units.addAll(asm
          .add(c.onPartial(1, '$a zurückzuführen', tAudio: 1.5).committed)
          .map((u) => u.$2));
      expect(c.decodeFrom, greaterThan(-1.0));
      expect(units, isEmpty);
      expect(asm.hasHeld, isTrue);
      units.addAll(asm
          .add(c.onFinal(1, '$a zurückzuführen.').committed)
          .map((u) => u.$2));
      expect(units, [
        'das ist vor allem auf den starken Export nach Frankreich und Italien zurückzuführen.'
      ]);
    });

    test('one unit per sentence, in order; unterminated remainder flushes', () {
      final c = SentenceCommitter();
      final asm = SentenceAssembler();
      final units = asm.add(c.onFinal(1, 'Eins. Zwei. Drei').committed);
      expect(units.map((u) => u.$2), ['Eins.', 'Zwei.']);
      expect(asm.flush()?.$2, 'Drei');
      expect(asm.flush(), isNull);
    });
  });
}
