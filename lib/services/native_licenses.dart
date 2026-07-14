import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'log_service.dart';

/// Register licenses for the *native* dependencies CrisperWeaver bundles —
/// `showLicensePage` only surfaces pub/Dart packages by default, so CrispASR,
/// whisper.cpp, and the ggml runtime would otherwise be invisible.
///
/// The license text is shipped as an asset under `assets/licenses/` and
/// registered via Flutter's built-in `LicenseRegistry`. That keeps everything
/// in one place — the same in-app screen that lists pub deps now lists the
/// FFI runtime too, no separate searchable JSON to maintain.
Future<void> registerNativeLicenses() async {
  LicenseRegistry.addLicense(() async* {
    try {
      final crispasr =
          await rootBundle.loadString('assets/licenses/CrispASR.txt');
      yield LicenseEntryWithLineBreaks(
        const ['CrispASR', 'whisper.cpp', 'ggml'],
        crispasr,
      );
    } catch (e, st) {
      Log.instance.w(
          'licenses', 'Failed to load CrispASR/whisper.cpp/ggml license',
          error: e, stack: st);
    }

    // --- Bundled native codec/runtime libraries. `showLicensePage` only
    // auto-lists pub packages, so these FFI-side binaries must be
    // registered explicitly or their (required) notices wouldn't appear. ---

    // libopus + libogg (Xiph.Org) — bundled as opus.dll/ogg.dll (Windows)
    // or statically linked (other platforms) for native .opus decode.
    yield const LicenseEntryWithLineBreaks(
      ['libopus', 'libogg (Xiph.Org)'],
      '''libopus  Copyright 2001-2023 Xiph.Org, Skype Limited, Octasic,
Jean-Marc Valin, Timothy B. Terriberry, CSIRO, Gregory Maxwell,
Mark Borgerding, Erik de Castro Lopo, and contributors.
libogg   Copyright (c) 2002-2020 Xiph.org Foundation.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

- Redistributions of source code must retain the above copyright notice,
  this list of conditions and the following disclaimer.
- Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.
- Neither the name of the Xiph.org Foundation nor the names of its
  contributors may be used to endorse or promote products derived from this
  software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES ARE DISCLAIMED. (BSD-3-Clause.)
Source: https://gitlab.xiph.org/xiph/opus  https://gitlab.xiph.org/xiph/ogg''',
    );

    // glint — clean-room MP3/AAC/Opus codec suite (bundled as glint.dll etc.)
    yield const LicenseEntryWithLineBreaks(
      ['glint (codec suite)'],
      '''MIT License. Copyright (c) 2026 glint contributors.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the above copyright notice and this permission
notice being included. THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF
ANY KIND.''',
    );

    // libmpv (media_kit desktop audio) — bundled only on Windows + Linux.
    yield const LicenseEntryWithLineBreaks(
      ['libmpv (media_kit, Windows/Linux only)'],
      '''Desktop audio playback on Windows and Linux uses just_audio_media_kit,
which bundles libmpv. libmpv is licensed under the GNU Lesser General Public
License, version 2.1 or later (LGPL-2.1-or-later). It is dynamically linked
and can be replaced by the user. Full license text and corresponding source:
https://github.com/mpv-player/mpv  (LICENSE / Copyright files therein).''',
    );

    // Short in-line attributions for upstream model weights.
    yield const LicenseEntryWithLineBreaks(
      ['Whisper model weights (OpenAI)'],
      '''Whisper model weights are distributed by OpenAI under the MIT License.
See: https://github.com/openai/whisper/blob/main/LICENSE

CrisperWeaver downloads Whisper GGML conversions hosted on HuggingFace
(ggerganov/whisper.cpp, cstr/whisper-ggml-quants). The weights remain under
their original licenses; only the on-disk GGML re-packing is attributable to
the respective HuggingFace repo maintainers.''',
    );
  });
}
