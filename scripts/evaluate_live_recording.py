#!/usr/bin/env python3
"""Compare raw/gain/light-cleanup room audio with the same loaded Cohere model.

Requires numpy, scipy, ffmpeg and the local CrispASR dylib. No cloud calls.
Writes playable snippets, transcripts and timings; differences are NOT WER.
"""
import argparse
import ctypes as C
import html
import json
from pathlib import Path
import subprocess
import time
import wave

import numpy as np
from scipy.signal import butter, sosfilt


def read_wav(path):
    with wave.open(str(path)) as w:
        if (w.getnchannels(), w.getsampwidth(), w.getframerate()) != (1, 2, 16000):
            raise ValueError('Expected 16 kHz mono PCM16 WAV')
        return np.frombuffer(w.readframes(w.getnframes()), '<i2').astype(np.float32) / 32768


def write_wav(path, a):
    with wave.open(str(path), 'wb') as w:
        w.setparams((1, 2, 16000, 0, 'NONE', 'not compressed'))
        w.writeframes(np.rint(np.clip(a, -1, 32767 / 32768) * 32768).astype('<i2').tobytes())


def levels(a):
    def db(v):
        return float(20 * np.log10(max(float(v), 1e-6)))
    return dict(rms_dbfs=db(np.sqrt(np.mean(a.astype(np.float64) ** 2))),
                peak_dbfs=db(np.max(np.abs(a))), clipped_samples=int(np.sum(np.abs(a) >= .9999)))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('audio', type=Path)
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--model', type=Path, required=True)
    p.add_argument('--lib', type=Path, required=True)
    args = p.parse_args()
    args.out.mkdir(parents=True, exist_ok=False)
    raw = read_wav(args.audio)
    # Target -26 dBFS RMS; at most +10 dB and preserve -3 dBFS peak headroom.
    gain = min(10 ** (10 / 20), 10 ** (-26 / 20) / max(np.sqrt(np.mean(raw ** 2)), 1e-6),
               10 ** (-3 / 20) / max(float(np.max(np.abs(raw))), 1e-6))
    variants = {'raw': raw, 'gain': raw * gain}
    write_wav(args.out / 'gain-full.wav', variants['gain'])
    hp = sosfilt(butter(2, 70, 'highpass', fs=16000, output='sos'), raw).astype(np.float32)
    write_wav(args.out / 'highpass-temp.wav', hp * gain)
    subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-i', str(args.out / 'highpass-temp.wav'),
                    '-af', 'afftdn=nr=6:nf=-40', str(args.out / 'cleanup-full.wav')], check=True)
    variants['cleanup'] = read_wav(args.out / 'cleanup-full.wav')
    (args.out / 'highpass-temp.wav').unlink()
    report = dict(source=str(args.audio.resolve()), model=str(args.model.resolve()),
                  lib=str(args.lib.resolve()), gain_db=float(20 * np.log10(gain)),
                  cleanup='70 Hz order-2 highpass, same gain, FFmpeg afftdn nr=6 nf=-40',
                  language='de', threads=3, levels={k: levels(v) for k, v in variants.items()}, rows=[])
    lib = C.CDLL(str(args.lib))
    P, I, S, F = C.c_void_p, C.c_int, C.c_char_p, C.POINTER(C.c_float)
    signatures = [
        ('crispasr_session_open_explicit', P, [S, S, I]),
        ('crispasr_session_close', None, [P]),
        ('crispasr_session_transcribe_lang', P, [P, F, I, S]),
        ('crispasr_session_result_n_segments', I, [P]),
        ('crispasr_session_result_segment_text', S, [P, I]),
        ('crispasr_session_result_free', None, [P]),
        ('crispasr_session_set_source_language', I, [P, S]),
        ('crispasr_session_set_translate', I, [P, I]),
        ('crispasr_session_set_max_new_tokens', I, [P, I]),
        ('crispasr_session_set_temperature', I, [P, C.c_float, C.c_uint64]),
    ]
    for name, ret, sig in signatures:
        f = getattr(lib, name)
        f.restype, f.argtypes = ret, sig
    t = time.monotonic()
    session = lib.crispasr_session_open_explicit(str(args.model).encode(), b'cohere', 3)
    if not session:
        raise RuntimeError('Failed to load Cohere')
    report['load_s'] = time.monotonic() - t
    lib.crispasr_session_set_source_language(session, b'de')
    lib.crispasr_session_set_translate(session, 0)
    lib.crispasr_session_set_max_new_tokens(session, 512)
    lib.crispasr_session_set_temperature(session, 0., 0)

    def decode(a):
        a = np.ascontiguousarray(a, dtype=np.float32)
        t = time.monotonic()
        r = lib.crispasr_session_transcribe_lang(session, a.ctypes.data_as(F), len(a), b'de')
        if not r:
            raise RuntimeError('Null transcription')
        try:
            text = ' '.join(lib.crispasr_session_result_segment_text(r, i).decode()
                            for i in range(lib.crispasr_session_result_n_segments(r)))
        finally:
            lib.crispasr_session_result_free(r)
        return text, time.monotonic() - t

    duration = len(raw) / 16000
    length = min(30, duration / 3)
    starts = [0., (duration - length) / 2, duration - length]
    try:
        decode(raw[:int(length * 16000)])  # warm-up, excluded from timings
        for n, start in enumerate(starts, 1):
            for name, audio in variants.items():
                clip = audio[round(start * 16000):round((start + length) * 16000)]
                filename = f'snippet-{n}-{name}.wav'
                write_wav(args.out / filename, clip)
                text, elapsed = decode(clip)
                row = dict(snippet=n, start_s=start, duration_s=len(clip) / 16000,
                           variant=name, file=filename, text=text, decode_s=elapsed)
                report['rows'].append(row)
                (args.out / 'results.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
                print(n, name, round(elapsed, 2), text, flush=True)
    finally:
        lib.crispasr_session_close(session)
    parts = ['<!doctype html><meta charset="utf-8"><title>Room microphone comparison</title>',
             '<style>body{font:17px system-ui;max-width:1000px;margin:30px auto}article{border-top:1px solid #ccc;padding:15px}audio{width:100%}</style>',
             '<h1>Cohere: raw, gain and light cleanup</h1>',
             '<p>Same captured audio and model. Transcripts are model outputs, not verified references. '
             'A changed transcript alone does not establish improved accuracy.</p>',
             '<pre>' + html.escape(json.dumps(report['levels'], indent=2)) + '</pre>']
    for row in report['rows']:
        parts.append(f'<article><h2>Snippet {row["snippet"]} · {row["start_s"]:.1f}s · {row["variant"]}</h2>'
                     f'<audio controls src="{row["file"]}"></audio><p>{html.escape(row["text"])}</p>'
                     f'<small>Decode: {row["decode_s"]:.2f}s / {row["duration_s"]:.1f}s audio</small></article>')
    (args.out / 'comparison.html').write_text('\n'.join(parts))


if __name__ == '__main__':
    main()
