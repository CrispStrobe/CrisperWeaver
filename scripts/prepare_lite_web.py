#!/usr/bin/env python3
"""Brand the already-compiled Lite web artifact without changing full assets."""
import json
from pathlib import Path

root = Path('build/web')
index = root / 'index.html'
index.write_text(index.read_text().replace('CrisperWeaver', 'CrisperWeaver Lite')
    .replace('Audio transcription, synthesis & voice cloning.',
             'Lite browser preview. Remote AI processing disabled.'))
manifest = root / 'manifest.json'
data = json.loads(manifest.read_text())
data.update(name='CrisperWeaver Lite', short_name='CW Lite',
    description='Lite browser preview. Native speech engines require the desktop app.')
manifest.write_text(json.dumps(data, indent=2) + '\n')
(root / 'flavor.json').write_text(json.dumps({
    'flavor': 'lite', 'remoteAi': False, 'modelDownloads': True,
    'nativeSpeech': False, 'speechEngine': 'mock',
}) + '\n')
