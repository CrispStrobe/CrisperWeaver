// Store-listing claim tripwire.
//
// WHY THIS FILE EXISTS
//
// The second EU AI Act audit (2026-08-02) corrected an inaccurate "no data is
// transmitted" claim in `docs/AI_ACT_RISK.md` §1 and rewrote `PRIVACY.md`
// around the two opt-in network features. `STORE_LISTING.md` was not part of
// that change and kept saying, for another day and two releases:
//
//   "All processing happens on your device — no cloud, no accounts, no data
//    collection."
//   "Everything runs on-device — no data leaves your phone or computer"
//
// That is the project's own recurring defect — a claim fixed where it was
// noticed and missed on a surface reached by another route — landing on the
// most public surface there is. Store metadata is also the one copy a user
// reads *before* installing, and the text that App Store Connect's App
// Privacy answers and Play's Data safety form are filled in from, so an
// absolute claim here propagates into two console declarations.
//
// This file does not check that the listing is well written. It asserts that
// the retracted absolutes have not come back, and that the listing still
// names the opt-in network features. Both directions matter: deleting the
// disclosure would pass a test that only banned phrases.
//
// WHEN THIS TEST FAILS
//
// Either a banned absolute was reintroduced — reword it against PRIVACY.md
// §3.1–3.3, which is the authority — or the disclosure was removed, in which
// case put it back. Do not relax the matcher: the claim is the thing under
// test.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String listing;

  setUpAll(() {
    // Collapse every run of whitespace to a single space before matching.
    //
    // The original defect read "no cloud, no accounts, no\ndata collection." —
    // wrapped across two lines by ordinary markdown prose reflow. A plain
    // substring check for "no data collection" passes on that text, so a
    // tripwire written the obvious way would have declared the file clean
    // while the claim sat in it. Prose wraps; the matcher has to not care.
    listing = File('STORE_LISTING.md')
        .readAsStringSync()
        .replaceAll(RegExp(r'\s+'), ' ');
  });

  group('no absolute offline claims', () {
    // Each of these was true of the app the listing described in July 2026
    // and false by 2 August 2026, when cloud transcription and BYOK cloud
    // cleanup shipped.
    const banned = <String, String>{
      'no data leaves':
          'Cloud transcription sends audio; cloud cleanup sends transcript '
              'text. See PRIVACY.md §3.2 and §3.3.',
      'no data collection':
          'The developer collects nothing, but two opt-in features transmit '
              'to third parties — say that instead of claiming neither.',
      'fully offline':
          'The app is offline-first, not fully offline. PRIVACY.md §3.2/§3.3.',
      'completely offline':
          'The app is offline-first, not completely offline.',
      'never leaves your device':
          'Only true of speaker profiles, voice embeddings and audio-to-LLM. '
              'Scope the claim to those rather than to everything.',
    };

    for (final entry in banned.entries) {
      test('"${entry.key}" does not appear', () {
        expect(
          listing.toLowerCase().contains(entry.key),
          isFalse,
          reason: 'STORE_LISTING.md must not claim "${entry.key}". '
              '${entry.value}',
        );
      });
    }
  });

  group('the opt-in network features stay disclosed', () {
    test('cloud transcription is named', () {
      expect(listing.toLowerCase(), contains('cloud transcription'));
    });

    test('cloud cleanup or summarisation is named', () {
      final lower = listing.toLowerCase();
      expect(
        lower.contains('summarisation') || lower.contains('summarization'),
        isTrue,
        reason: 'The BYOK cloud text path sends transcript text to a '
            'third-party endpoint and has to be disclosed.',
      );
    });

    test('both are described as off by default', () {
      expect(listing.toLowerCase(), contains('off by default'));
    });

    test('model downloads are disclosed', () {
      expect(listing.toLowerCase(), contains('huggingface'));
    });

    test('the console questionnaire section survives', () {
      // Deleting this is how the listing text and the App Store Connect / Play
      // answers drift apart again.
      expect(listing, contains('App Privacy questionnaire'));
    });
  });

  test('the privacy policy URL is still published', () {
    // App Store Connect and Play both require it, and it is the document this
    // listing defers to for detail.
    expect(listing, contains('PRIVACY.md'));
  });
}
