// §5.25.10 — SegmentTag enum: JSON round-trip, list serialization.

import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/models/segment_tag.dart';

void main() {
  group('SegmentTag', () {
    test('every value has a non-empty label and emoji', () {
      for (final tag in SegmentTag.values) {
        expect(tag.label, isNotEmpty, reason: '${tag.name} label');
        expect(tag.emoji, isNotEmpty, reason: '${tag.name} emoji');
      }
    });

    test('toJson / fromJson round-trip for every value', () {
      for (final tag in SegmentTag.values) {
        final json = tag.toJson();
        final restored = SegmentTag.fromJson(json);
        expect(restored, tag, reason: '${tag.name} round-trip');
      }
    });

    test('fromJson returns null for unknown string', () {
      expect(SegmentTag.fromJson('nonexistent'), isNull);
    });

    test('fromJson returns null for null input', () {
      expect(SegmentTag.fromJson(null), isNull);
    });

    test('listToJson / listFromJson round-trip', () {
      final tags = [SegmentTag.bookmark, SegmentTag.actionItem, SegmentTag.question];
      final json = SegmentTag.listToJson(tags);
      expect(json, ['bookmark', 'actionItem', 'question']);
      final restored = SegmentTag.listFromJson(json);
      expect(restored, tags);
    });

    test('listFromJson skips unknown entries', () {
      final restored = SegmentTag.listFromJson(['bookmark', 'fake', 'important']);
      expect(restored, [SegmentTag.bookmark, SegmentTag.important]);
    });

    test('listFromJson handles null input', () {
      expect(SegmentTag.listFromJson(null), isEmpty);
    });

    test('enum has exactly 7 values (regression guard)', () {
      expect(SegmentTag.values.length, 7);
    });
  });
}
