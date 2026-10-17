import 'package:crisper_weaver/services/live_translate/revision_planner.dart';
import 'package:flutter_test/flutter_test.dart';

RevisionSentence s(int key, int utt, [String lang = 'de']) =>
    RevisionSentence(key: key, utterance: utt, lang: lang, text: 'S$key.');

void main() {
  test('a paragraph closes when its utterance ends', () {
    final p = RevisionPlanner()
      ..add(s(0, 1))
      ..add(s(1, 1));
    expect(p.queued, isEmpty);
    p.utteranceEnded(1);
    expect(p.queued.single.keys, [0, 1]);
    expect(p.queued.single.text, 'S0. S1.');
  });

  test('…or after four sentences of continuous speech', () {
    final p = RevisionPlanner();
    for (var i = 0; i < 5; i++) {
      p.add(s(i, 1));
    }
    expect(p.queued.single.keys, [0, 1, 2, 3]);
    p.utteranceEnded(1);
    expect(p.queued.last.keys, [4]);
  });

  test('a new utterance or language starts a new paragraph', () {
    final p = RevisionPlanner()
      ..add(s(0, 1))
      ..add(s(1, 2))
      ..add(s(2, 2, 'en'));
    expect(p.queued.map((q) => q.keys), [
      [0],
      [1]
    ]);
    expect(p.queued.last.lang, 'de');
    p.flush();
    expect(p.queued.last.lang, 'en');
  });

  test('only while the fast translator is idle', () {
    final p = RevisionPlanner()
      ..add(s(0, 1))
      ..utteranceEnded(1);
    expect(p.next(fastIdle: false), isNull);
    expect(p.next(fastIdle: true)?.keys, [0]);
    expect(p.next(fastIdle: true), isNull);
  });

  test('it may lag but never piles up: the oldest paragraph is dropped', () {
    final p = RevisionPlanner();
    for (var u = 0; u < 5; u++) {
      p
        ..add(s(u, u))
        ..utteranceEnded(u);
    }
    expect(p.queued.map((q) => q.keys.single), [2, 3, 4]);
    expect(p.skipped, 2);
  });

  test('an ended utterance that is not the open one closes nothing', () {
    final p = RevisionPlanner()..add(s(0, 2));
    p.utteranceEnded(1);
    expect(p.queued, isEmpty);
  });
}
