// A catalogue description that promises voice cloning is a promise the
// Synthesize screen has to keep. The screen offers a reference-clip field
// only for SynthesizeScreen.cloneCapableBackends, so any TTS entry outside
// that set that still says "clone" advertises a feature the user cannot
// reach — which is how Zonos read "speaker clone" for months while its
// engine arm was a stub (CrispASR 0.8.34 dropped the claim upstream).

import 'package:crisper_weaver/screens/synthesize_screen.dart';
import 'package:crisper_weaver/services/model_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

/// Backends that clone from something other than a recorded clip, so they
/// may say "clone" without being in cloneCapableBackends.
const _clonesWithoutAClip = <String>{
  // Speaker profile JSON, not a reference WAV.
  'outetts',
};

bool _claimsCloning(String description) =>
    description.toLowerCase().contains('clon');

void main() {
  bool mayClaim(String backend) =>
      SynthesizeScreen.cloneCapableBackends.contains(backend) ||
      _clonesWithoutAClip.contains(backend);

  test('no TTS model claims cloning its backend cannot do', () {
    final offenders = [
      for (final m in ModelCatalog.crispasrBackendModels.values)
        if (m.kind == ModelKind.tts &&
            _claimsCloning(m.description) &&
            !mayClaim(m.backend))
          '${m.name} [${m.backend}]',
    ];
    expect(offenders, isEmpty);
  });

  test('no TTS backend repo claims cloning its backend cannot do', () {
    final offenders = [
      for (final e in ModelCatalog.backendRepos.entries)
        if (e.value.kind == ModelKind.tts &&
            _claimsCloning(e.value.description) &&
            !mayClaim(e.value.backend))
          '${e.key} [${e.value.backend}]',
    ];
    expect(offenders, isEmpty);
  });
}
