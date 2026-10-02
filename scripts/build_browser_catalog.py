"""Expose native ASR candidates for the browser's explicit experimental override."""
import json
from pathlib import Path

models = json.loads(Path('assets/models/catalog.json').read_text())
target = Path('build/web/speech/native-models.json')
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(json.dumps([
    dict(id=m['name'], name=m['displayName'], url=m['url'],
         sizeBytes=m['sizeBytes'], backend=m['backend'],
         languages=m.get('languages', []),
         recommended=m['name'] == 'stt-en-fastconformer-ctc-large-q4_k',
         companions=[dict(path='/tokenizer.bin', url=m['url'].rsplit('/', 1)[0] + '/tokenizer.bin')]
         if m['backend'] == 'moonshine' else [])
    for m in models if m.get('kind') == 'asr'
], indent=2) + '\n')
