// §5.25.4 — SpeakerVocab model: JSON round-trip, merge, file I/O.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:crisper_weaver/models/speaker_vocab.dart';

void main() {
  group('SpeakerVocab JSON', () {
    test('toJson / fromJson round-trip', () {
      const original = SpeakerVocab(
        speakerName: 'Alice',
        terms: ['Kubernetes', 'kubectl', 'etcd'],
      );
      final json = original.toJson();
      final restored = SpeakerVocab.fromJson(json);
      expect(restored.speakerName, 'Alice');
      expect(restored.terms, ['Kubernetes', 'kubectl', 'etcd']);
    });

    test('empty terms round-trip', () {
      const original = SpeakerVocab(speakerName: 'Bob', terms: []);
      final restored = SpeakerVocab.fromJson(original.toJson());
      expect(restored.terms, isEmpty);
    });
  });

  group('mergeForSpeakers', () {
    final vocabs = [
      const SpeakerVocab(
          speakerName: 'Alice', terms: ['Kubernetes', 'kubectl']),
      const SpeakerVocab(
          speakerName: 'Bob', terms: ['PostgreSQL', 'pgvector']),
      const SpeakerVocab(
          speakerName: 'Carol', terms: ['React', 'TypeScript']),
    ];

    test('merges terms for identified speakers only', () {
      final merged =
          SpeakerVocab.mergeForSpeakers(vocabs, {'Alice', 'Carol'});
      expect(merged, containsAll(['Kubernetes', 'kubectl', 'React', 'TypeScript']));
      expect(merged, isNot(contains('PostgreSQL')));
    });

    test('empty identified set → empty merge', () {
      final merged = SpeakerVocab.mergeForSpeakers(vocabs, {});
      expect(merged, isEmpty);
    });

    test('deduplicates shared terms', () {
      final overlapping = [
        const SpeakerVocab(speakerName: 'A', terms: ['shared', 'unique-a']),
        const SpeakerVocab(speakerName: 'B', terms: ['shared', 'unique-b']),
      ];
      final merged =
          SpeakerVocab.mergeForSpeakers(overlapping, {'A', 'B'});
      expect(merged.where((t) => t == 'shared').length, 1);
      expect(merged, containsAll(['shared', 'unique-a', 'unique-b']));
    });

    test('unknown speaker name is silently skipped', () {
      final merged =
          SpeakerVocab.mergeForSpeakers(vocabs, {'Unknown'});
      expect(merged, isEmpty);
    });
  });

  group('SpeakerVocab file I/O', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('crisper_vocab_test_');
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('save + load round-trip', () async {
      const vocab = SpeakerVocab(
        speakerName: 'Alice',
        terms: ['Kubernetes', 'kubectl'],
      );
      await vocab.save(tmp.path);

      final loaded = await SpeakerVocab.load(tmp.path, 'Alice');
      expect(loaded, isNotNull);
      expect(loaded!.speakerName, 'Alice');
      expect(loaded.terms, ['Kubernetes', 'kubectl']);
    });

    test('load returns null for missing file', () async {
      final loaded = await SpeakerVocab.load(tmp.path, 'Nobody');
      expect(loaded, isNull);
    });

    test('delete removes the file', () async {
      const vocab = SpeakerVocab(speakerName: 'Bob', terms: ['test']);
      await vocab.save(tmp.path);
      expect(await File(p.join(tmp.path, 'Bob.vocab.json')).exists(), isTrue);

      await SpeakerVocab.delete(tmp.path, 'Bob');
      expect(await File(p.join(tmp.path, 'Bob.vocab.json')).exists(), isFalse);
    });

    test('listAll returns all vocab files', () async {
      const a = SpeakerVocab(speakerName: 'A', terms: ['x']);
      const b = SpeakerVocab(speakerName: 'B', terms: ['y']);
      await a.save(tmp.path);
      await b.save(tmp.path);

      // Also drop a non-vocab file to make sure it's skipped.
      await File(p.join(tmp.path, 'noise.json'))
          .writeAsString(jsonEncode({'unrelated': true}));

      final all = await SpeakerVocab.listAll(tmp.path);
      expect(all.length, 2);
      expect(all.map((v) => v.speakerName).toSet(), {'A', 'B'});
    });

    test('listAll skips corrupt files', () async {
      await File(p.join(tmp.path, 'bad.vocab.json'))
          .writeAsString('not valid json{{{');
      const good = SpeakerVocab(speakerName: 'Good', terms: ['ok']);
      await good.save(tmp.path);

      final all = await SpeakerVocab.listAll(tmp.path);
      expect(all.length, 1);
      expect(all.first.speakerName, 'Good');
    });

    test('listAll on nonexistent dir → empty', () async {
      final all = await SpeakerVocab.listAll('/tmp/no-such-dir-xyz');
      expect(all, isEmpty);
    });
  });
}
