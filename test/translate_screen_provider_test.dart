// Unit tests for TranslateScreenNotifier (§8.2).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/providers/translate_screen_provider.dart';

void main() {
  late ProviderContainer container;
  late TranslateScreenNotifier n;

  TranslateScreenState readState() =>
      container.read(translateScreenProvider);

  setUp(() {
    container = ProviderContainer();
    container.read(translateScreenProvider);
    n = container.read(translateScreenProvider.notifier);
  });

  tearDown(() => container.dispose());

  test('initial state has sensible defaults', () {
    final s = readState();
    expect(s.models, isEmpty);
    expect(s.loading, isTrue);
    expect(s.busy, isFalse);
    expect(s.selectedModel, isNull);
    expect(s.srcLang, 'en');
    expect(s.tgtLang, 'de');
    expect(s.maxTokens, 200);
  });

  test('setLoading updates loading flag', () {
    n.setLoading(false);
    expect(readState().loading, isFalse);
    n.setLoading(true);
    expect(readState().loading, isTrue);
  });

  test('setBusy updates busy flag', () {
    n.setBusy(true);
    expect(readState().busy, isTrue);
    n.setBusy(false);
    expect(readState().busy, isFalse);
  });

  test('setSelectedModel updates selection', () {
    n.setSelectedModel('m2m100-418m-q4_k');
    expect(readState().selectedModel, 'm2m100-418m-q4_k');
  });

  test('setSrcLang and setTgtLang update languages', () {
    n.setSrcLang('fr');
    n.setTgtLang('es');
    expect(readState().srcLang, 'fr');
    expect(readState().tgtLang, 'es');
  });

  test('setMaxTokens updates max tokens', () {
    n.setMaxTokens(512);
    expect(readState().maxTokens, 512);
  });

  test('swapLanguages exchanges src and tgt', () {
    n.setSrcLang('fr');
    n.setTgtLang('ja');
    n.swapLanguages();
    expect(readState().srcLang, 'ja');
    expect(readState().tgtLang, 'fr');
  });

  test('copyWith clearSelectedModel resets to null', () {
    n.setSelectedModel('test');
    final s = readState().copyWith(clearSelectedModel: true);
    expect(s.selectedModel, isNull);
  });

  test('multiple mutations are independent', () {
    n.setLoading(false);
    n.setBusy(true);
    n.setSrcLang('zh');
    final s = readState();
    expect(s.loading, isFalse);
    expect(s.busy, isTrue);
    expect(s.srcLang, 'zh');
    // Unchanged defaults preserved
    expect(s.tgtLang, 'de');
    expect(s.maxTokens, 200);
  });
}
