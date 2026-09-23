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
import os
import re
import subprocess
import sys
import tempfile

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
    # Breeze-TTS-2 dropped both ends of the sentence through the session.
    # The same sentence through the CLI says whether that is the runtime or
    # the session path.
    "bt2-tts-cli": dict(model="breeze-tts-2-q4_k.gguf", backend="bt2-tts",
                        lang="en", text=EN, cli=True,
                        codec="qwen3-tts-tokenizer-12hz.gguf"),
    # Hojo-ASR (4.4 GB) in a closed loop: Pocket TTS German speaks a
    # sentence, Hojo transcribes it instead of Parakeet.
    "hojo-asr-de": dict(model="pocket-tts-german-q8_0.gguf",
                        backend="pocket-tts", lang="de", text=DE, clone=True,
                        asr=("hojo-asr-multi-v1-q4_k.gguf", "hojo-asr")),
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


def synth_cli(models, c):
    """Synthesise through the crispasr CLI ($CRISPASR_BIN) instead of the
    session ABI, provenance opt-outs on so the WAV holds only the speech."""
    out = os.path.join(tempfile.mkdtemp(), "cli.wav")
    cmd = [os.environ["CRISPASR_BIN"], "--backend", c["backend"],
           "-m", f"{models}/{c['model']}", "--tts", c["text"],
           "--tts-output", out, "--seed", "7",
           "--no-spoken-disclaimer", "--accept-marking-responsibility"]
    if c.get("codec"):
        cmd += ["--codec-model", f"{models}/{c['codec']}"]
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL)
    return read_wav(out)


def read_wav(path):
    """Mono float32 + rate from a WAV, PCM16 or IEEE float32 (the stdlib
    wave module rejects the latter)."""
    b = open(path, "rb").read()
    assert b[:4] == b"RIFF" and b[8:12] == b"WAVE", path
    i, fmt, sr, ch, bits, data = 12, None, None, None, None, None
    while i + 8 <= len(b):
        cid, n = b[i:i + 4], int.from_bytes(b[i + 4:i + 8], "little")
        body = b[i + 8:i + 8 + n]
        if cid == b"fmt ":
            fmt = int.from_bytes(body[0:2], "little")
            ch = int.from_bytes(body[2:4], "little")
            sr = int.from_bytes(body[4:8], "little")
            bits = int.from_bytes(body[14:16], "little")
        elif cid == b"data":
            data = body
        i += 8 + n + (n & 1)
    if fmt == 3 or (fmt == 0xFFFE and bits == 32):
        pcm = np.frombuffer(data, dtype="<f4")
    else:
        pcm = np.frombuffer(data, dtype="<i2").astype(np.float32) / 32768.0
    if ch and ch > 1:
        pcm = pcm.reshape(-1, ch).mean(axis=1)
    return pcm.astype(np.float32), sr


def synth(models, c, jfk, clone):
    s = crispasr.Session(f"{models}/{c['model']}", backend=c["backend"])
    try:
        if c.get("codec"):
            s.set_codec_path(f"{models}/{c['codec']}")
        if clone:
            s.set_voice(jfk, JFK_TEXT)
        s.set_tts_seed(7)
        pcm = np.asarray(s.synthesize(c["text"]), dtype=np.float32)
        # 0 = "this dylib does not report a rate"; the app falls back to
        # 24 kHz (TtsService.kFallbackOutputSampleRate), so do the same.
        sr = s.output_sample_rate() or 24000
        return pcm, sr
    finally:
        s.close()


def main():
    models, jfk, names = sys.argv[1], sys.argv[2], sys.argv[3:]
    parakeet = crispasr.Session(f"{models}/parakeet-tdt-0.6b-v3-q4_k.gguf",
                                backend="parakeet")
    failed = []
    for name in names:
        c = CASES[name]
        lang, text = c["lang"], c["text"]
        if c.get("cli"):
            pcm, sr = synth_cli(models, c)
        else:
            pcm, sr = synth(models, c, jfk, bool(c.get("clone")))
        note = ""
        if c.get("clone"):
            # A clone that is silently ignored still passes the round trip.
            # Same seed and text without the reference: the audio must differ.
            base, _ = synth(models, c, jfk, False)
            same = len(base) == len(pcm) and np.array_equal(base, pcm)
            note = "; reference IGNORED (identical to no-reference)" if same \
                else "; reference applied (differs from no-reference)"
        asr = parakeet
        if c.get("asr"):
            asr = crispasr.Session(f"{models}/{c['asr'][0]}", backend=c["asr"][1])
        heard = " ".join(
            seg.text for seg in asr.transcribe(to_16k(pcm, sr), language=lang))
        if asr is not parakeet:
            asr.close()
        want = words(text)
        got = set(words(heard))
        hit = sum(1 for w in want if w in got) / len(want)
        ok = hit >= 0.8
        tag = ("INFO" if c.get("informational") else
               "PASS" if ok else "FAIL")
        if note.startswith("; reference IGNORED"):
            ok, tag = False, "FAIL"
        print(f"{tag} {name}: {len(pcm) / sr:.2f}s @{sr} Hz,"
              f" {hit:.0%} of words heard: {heard!r}{note}", flush=True)
        if not ok and not c.get("informational"):
            failed.append(name)
    parakeet.close()
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
