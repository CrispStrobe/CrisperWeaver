"""Refresh immutable browser model revisions and checksums from the HF Hub.

Run deliberately when updating models; builds consume the checked-in lock.
Large LFS files use Hub SHA256 metadata, small files are hashed directly.
"""
import concurrent.futures
import hashlib
import json
import re
import subprocess
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
curated = json.loads(subprocess.check_output([
    'node', '-e', "require('./web/speech/catalog.js');process.stdout.write(JSON.stringify(CW_SPEECH_MODELS))"
], cwd=ROOT))
urls = set(re.findall(r"https://huggingface.co/[^'\"\s]+", (ROOT / 'web/speech/catalog.js').read_text()))
# The generated Phonon filenames are not literal URLs in catalog.js.
urls = {u for u in urls if not u.endswith('/phonon2-')}
for quant in ('q4_k', 'q8_0', 'f16'):
    urls.add('https://huggingface.co/cstr/phonon2-GGUF/resolve/3ed3e6ad6e7ce63affffeede37328ff756efaa2f/phonon2-' + quant + '.gguf')
native = json.loads((ROOT / 'assets/models/catalog.json').read_text())
for model in native:
    if model.get('kind') == 'asr':
        urls.add(model['url'])
        if model['backend'] == 'moonshine':
            urls.add(model['url'].rsplit('/', 1)[0] + '/tokenizer.bin')
urls.update([
    'https://huggingface.co/cstr/kokoro-82m-GGUF/resolve/main/kokoro-82m-q8_0.gguf',
    'https://huggingface.co/cstr/kokoro-voices-GGUF/resolve/main/kokoro-voice-af_heart.gguf',
    'https://huggingface.co/datasets/cstr/g2p-dicts/resolve/main/cmudict.dict',
])
groups = {}
for url in urls:
    match = re.fullmatch(r'https://huggingface.co/(datasets/)?([^/]+/[^/]+)/resolve/([^/]+)/(.+)', url)
    if not match:
        raise ValueError('Model URL cannot be pinned: ' + url)
    dataset, repo, revision, file = match.groups()
    groups.setdefault((dataset or '', repo, revision), set()).add(file)
for model in curated['onnx']:
    groups[('', model['repo'], 'main')] = None

def read(url):
    for attempt in range(4):
        try:
            with urllib.request.urlopen(url, timeout=60) as response:
                return response.read()
        except Exception:
            if attempt == 3:
                raise
            time.sleep(2 ** attempt)

def lock(group):
    (dataset, repo, revision), wanted = group
    kind = 'datasets' if dataset else 'models'
    info = json.loads(read(f'https://huggingface.co/api/{kind}/{repo}/revision/{revision}?blobs=true'))
    sha = info['sha']
    files = {}
    for entry in info['siblings']:
        file = entry['rfilename']
        if wanted is not None and file not in wanted:
            continue
        if wanted is None and not (file.endswith('.json') or file.endswith('.txt') or file.endswith('.model') or file.endswith('.tiktoken') or file.endswith('.onnx') and 'quantized' in file):
            continue
        url = f'https://huggingface.co/{dataset}{repo}/resolve/{sha}/{file}'
        lfs = entry.get('lfs') or {}
        digest = lfs.get('sha256')
        size = entry.get('size') or lfs.get('size')
        if not digest:
            data = read(url)
            digest, size = hashlib.sha256(data).hexdigest(), len(data)
        files[file] = dict(url=url, sha256=digest, size=size)
    missing = (wanted or set()) - files.keys()
    if missing:
        raise ValueError(f'{repo}: missing files {sorted(missing)}')
    print(f'Locked {dataset}{repo}: {len(files)} files', flush=True)
    return dataset + repo, dict(revision=sha, files=files)

with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
    results = dict(pool.map(lock, groups.items()))
target = ROOT / 'web/speech/model-lock.json'
target.write_text(json.dumps(dict(version=1, repositories=dict(sorted(results.items()))), indent=2) + '\n')
print(f'Wrote {target.relative_to(ROOT)}', flush=True)
