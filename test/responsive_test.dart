// Coverage for utils/responsive.dart's viewport-clamp helpers, which
// are what stop AlertDialog content from overflowing on phones / narrow
// desktop windows. The math is pure (math.min / math.max around a
// MediaQuery width), but the helpers read MediaQuery.sizeOf(context),
// so we drive them through a minimal MediaQuery host rather than calling
// them bare. No go_router / l10n / FFI is exercised.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/utils/responsive.dart';

/// Wraps [child] in a MediaQuery with a fixed [size] and captures the
/// BuildContext so the helper-under-test can be invoked against it.
Future<BuildContext> _contextWithSize(
  WidgetTester tester,
  Size size,
) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: size),
      child: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return captured;
}

void main() {
  group('Breakpoints', () {
    test('phone breakpoint is narrower than compact', () {
      // The whole adaptive scheme assumes phone < compact; if these
      // ever cross, isPhoneWidth would imply !isCompactWidth absurdly.
      expect(Breakpoints.phone, lessThan(Breakpoints.compact));
    });
  });

  group('responsiveDialogWidth', () {
    testWidgets('returns the designed width on a wide viewport', (t) async {
      final ctx = await _contextWithSize(t, const Size(1400, 900));
      expect(responsiveDialogWidth(ctx, designed: 560), 560);
    });

    testWidgets('clamps to viewport minus 32px on a narrow viewport',
        (t) async {
      final ctx = await _contextWithSize(t, const Size(360, 800));
      // 360 - 32 = 328, which is < 560, so we get the clamp.
      expect(responsiveDialogWidth(ctx, designed: 560), 328);
    });

    testWidgets('default designed width is 560', (t) async {
      final ctx = await _contextWithSize(t, const Size(2000, 1200));
      expect(responsiveDialogWidth(ctx), 560);
    });

    testWidgets('never goes negative on a zero-width viewport', (t) async {
      final ctx = await _contextWithSize(t, const Size(0, 0));
      expect(responsiveDialogWidth(ctx, designed: 560), 0);
    });
  });

  group('responsiveDialogHeight', () {
    testWidgets('returns the designed height when it fits', (t) async {
      final ctx = await _contextWithSize(t, const Size(1400, 1200));
      expect(responsiveDialogHeight(ctx, designed: 560, chrome: 200), 560);
    });

    testWidgets('clamps to viewport minus chrome when short', (t) async {
      final ctx = await _contextWithSize(t, const Size(360, 640));
      // 640 - 200 chrome = 440, which is < 560.
      expect(responsiveDialogHeight(ctx, designed: 560, chrome: 200), 440);
    });

    testWidgets('floors at 160 on a very short viewport', (t) async {
      final ctx = await _contextWithSize(t, const Size(360, 250));
      // 250 - 200 = 50, below the 160 floor → 160.
      expect(responsiveDialogHeight(ctx, designed: 560, chrome: 200), 160);
    });
  });

  group('isPhoneWidth / isCompactWidth', () {
    testWidgets('true below the phone breakpoint', (t) async {
      final ctx = await _contextWithSize(t, Size(Breakpoints.phone - 1, 800));
      expect(isPhoneWidth(ctx), isTrue);
      expect(isCompactWidth(ctx), isTrue);
    });

    testWidgets('phone breakpoint width itself is NOT phone (strict <)',
        (t) async {
      final ctx = await _contextWithSize(t, Size(Breakpoints.phone, 800));
      expect(isPhoneWidth(ctx), isFalse);
    });

    testWidgets('between phone and compact: compact yes, phone no', (t) async {
      final mid = (Breakpoints.phone + Breakpoints.compact) / 2;
      final ctx = await _contextWithSize(t, Size(mid, 800));
      expect(isPhoneWidth(ctx), isFalse);
      expect(isCompactWidth(ctx), isTrue);
    });

    testWidgets('wide viewport is neither phone nor compact', (t) async {
      final ctx = await _contextWithSize(t, const Size(1200, 900));
      expect(isPhoneWidth(ctx), isFalse);
      expect(isCompactWidth(ctx), isFalse);
    });
  });
}
