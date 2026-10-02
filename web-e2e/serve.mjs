// Local production-bundle server with the same isolation headers as Vercel.
import http from 'node:http';
import { stat, readFile } from 'node:fs/promises';
import path from 'node:path';
const root = path.resolve(process.argv[2] || '../build/web');
const types = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript',
  '.wasm': 'application/wasm', '.json': 'application/json', '.png': 'image/png', '.wav': 'audio/wav' };
http.createServer(async (req, res) => {
  try {
    const pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
    let file = path.resolve(root, '.' + pathname);
    if (!file.startsWith(root + path.sep) && file !== root) { res.writeHead(403); res.end(); return; }
    try { if ((await stat(file)).isDirectory()) file = path.join(file, 'index.html'); }
    catch { file = path.join(root, 'index.html'); }
    const bytes = await readFile(file);
    const headers = { 'Content-Type': types[path.extname(file)] || 'application/octet-stream',
      'Cross-Origin-Opener-Policy': 'same-origin', 'Cross-Origin-Embedder-Policy': 'require-corp',
      'Cache-Control': 'no-store', 'Accept-Ranges': 'bytes' };
    const range = /^bytes=(\d+)-(\d*)$/.exec(req.headers.range || '');
    if (range) {
      const start = Number(range[1]), end = Math.min(Number(range[2] || bytes.length - 1), bytes.length - 1);
      res.writeHead(206, { ...headers, 'Content-Range': `bytes ${start}-${end}/${bytes.length}`,
        'Content-Length': end - start + 1 }); res.end(bytes.subarray(start, end + 1));
    } else { res.writeHead(200, { ...headers, 'Content-Length': bytes.length }); res.end(bytes); }
  } catch { res.writeHead(404); res.end(); }
}).listen(Number(process.env.PORT || 8765), '127.0.0.1', () => console.log('Web bundle on http://127.0.0.1:8765'));
