#!/usr/bin/env python3
"""TTS → ASR round trip through CrispASR's session API, for models too large
to run on the development VPS (see .github/workflows/live-tts.yml).

Each case opens the model the way CrisperWeaver does (explicit backend,
companion as a sibling file, optional reference voice), synthesises one
sentence, transcribes it with Parakeet TDT 0.6B v3 and fails unless most of
the sentence's words come back. A model that loads and emits audio but
produces noise fails here, which "synthesize returned samples" would not.

Usage: live_tts_check.py MODELS_DIR JFK_WAV CASE [CASE ...]
Cases: see CASES. `expect_fail` cases are questions, not assertions: they
report what happens without failing the run.
"""
import re
import sys

import numpy as np
import crispasr

JFK_TEXT = ("And so, my fellow Americans, ask not what your country can do "
            "for you, ask what you can do for your country.")

EN = "The quick brown fox jumps over the lazy dog."
DE = "Guten Morgen, wie geht es dir heute?"

CASES = {
    # name: dict(model, backend, lang, text, clone, codec, informational)
    "fireredtts3": dict(model="fireredtts3-base-q4_k.gguf",
                        backend="fireredtts3", lang="en", text=EN),
    "fireredtts3-clone": dict(model="fireredtts3-base-q4_k.gguf",
                              backend="fireredtts3", lang="en", text=EN,
                              clone=True),
    "bt2-tts": dict(model="breeze-tts-2-q4_k.gguf", backend="bt2-tts",
                    lang="en", text=EN),
    "pocket-tts-de-clone": dict(model="pocket-tts-german-q8_0.gguf",
                                backend="pocket-tts", lang="de", text=DE,
                                clone=True),
    # Does English Pocket TTS speak without a reference? (German does not.)
    "pocket-tts-en-novoice": dict(model="pocket-tts-english-f16.gguf",
                                  backend="pocket-tts", lang="en", text=EN,
                                  informational=True),
    # Kartoffelbox is a Turbo-architecture T3: the registry pairs it with
    # the Turbo S3Gen, the app catalogue with the standard one.
    "kartoffelbox-turbo-s3gen": dict(model="kartoffelbox-turbo-t3-q8_0.gguf",
                                     backend="chatterbox", lang="de", text=DE,
                                     codec="chatterbox-turbo-s3gen-q8_0.gguf"),
    "kartoffelbox-std-s3gen": dict(model="kartoffelbox-turbo-t3-q8_0.gguf",
                                   backend="chatterbox", lang="de", text=DE,
                                   codec="chatterbox-s3gen-q8_0.gguf",
                                   informational=True),
}


def words(s):
    return re.findall(r"[a-z']+", s.lower())


def to_16k(pcm, sr):
    if sr == 16000:
        return pcm.astype(np.float32)
    n = int(len(pcm) * 16000 / sr)
    x = np.linspace(0, len(pcm) - 1, n)
    return np.interp(x, np.arange(len(pcm)), pcm).astype(np.float32)


def main():
    models, jfk, names = sys.argv[1], sys.argv[2], sys.argv[3:]
    asr = crispasr.Session(f"{models}/parakeet-tdt-0.6b-v3-q4_k.gguf",
                           backend="parakeet")
    failed = []
    for name in names:
        c = CASES[name]
        lang, text = c["lang"], c["text"]
        s = crispasr.Session(f"{models}/{c['model']}", backend=c["backend"])
        try:
            if c.get("codec"):
                s.set_codec_path(f"{models}/{c['codec']}")
            if c.get("clone"):
                s.set_voice(jfk, JFK_TEXT)
            s.set_tts_seed(7)
            pcm = np.asarray(s.synthesize(text), dtype=np.float32)
            sr = s.output_sample_rate()
        finally:
            s.close()
        heard = " ".join(
            seg.text for seg in asr.transcribe(to_16k(pcm, sr), language=lang))
        want = words(text)
        got = set(words(heard))
        hit = sum(1 for w in want if w in got) / len(want)
        ok = hit >= 0.8
        tag = ("INFO" if c.get("informational") else
               "PASS" if ok else "FAIL")
        print(f"{tag} {name}: {len(pcm) / sr:.2f}s @{sr} Hz,"
              f" {hit:.0%} of words heard: {heard!r}", flush=True)
        if not ok and not c.get("informational"):
            failed.append(name)
    asr.close()
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
