#!/usr/bin/env python3
"""Serve a compiled app with current speech assets for local browser checks."""
import argparse
import functools
import http.server
import pathlib
import io
import re
import urllib.parse

parser = argparse.ArgumentParser()
parser.add_argument('--app', required=True)
parser.add_argument('--port', type=int, default=8766)
parser.add_argument('--no-isolation', action='store_true')
args = parser.parse_args()
assets = pathlib.Path(__file__).resolve().parents[1] / 'web'


class Handler(http.server.SimpleHTTPRequestHandler):
    def translate_path(self, path):
        relative = urllib.parse.unquote(urllib.parse.urlsplit(path).path).lstrip('/')
        if relative.startswith(('speech/', 'wasm/')):
            candidate = (assets / relative).resolve()
            if candidate.is_relative_to(assets) and candidate.is_file():
                return str(candidate)
        return super().translate_path(path)

    def send_head(self):
        requested = self.headers.get('Range')
        match = re.fullmatch(r'bytes=(\d+)-(\d*)', requested or '')
        target = pathlib.Path(self.translate_path(self.path))
        if match and target.is_file():
            size = target.stat().st_size
            start = int(match[1])
            end = min(int(match[2]) if match[2] else size - 1, size - 1)
            if start > end or start >= size:
                self.send_error(416, 'Invalid range'); return None
            with target.open('rb') as source:
                source.seek(start); data = source.read(end - start + 1)
            self.send_response(206)
            self.send_header('Content-Type', self.guess_type(str(target)))
            self.send_header('Content-Length', str(len(data)))
            self.send_header('Content-Range', f'bytes {start}-{end}/{size}')
            self.end_headers()
            return io.BytesIO(data)
        return super().send_head()

    def end_headers(self):
        if not args.no_isolation:
            self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
            self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()


http.server.ThreadingHTTPServer(
    ('127.0.0.1', args.port),
    functools.partial(Handler, directory=args.app),
).serve_forever()
