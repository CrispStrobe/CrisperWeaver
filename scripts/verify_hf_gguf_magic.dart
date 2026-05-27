// HF-blob sanity check — fetches the first 8 bytes of every catalogue
// URL and confirms it starts with the GGUF / ggml magic bytes.
//
// Caught upstream-broken blobs on first run (issue #12):
//   * cstr/funasr-nano-GGUF/funasr-nano-2512-q4_k.gguf
//   * cstr/funasr-mlt-nano-GGUF/funasr-mlt-nano-2512-q4_k.gguf
// Both had a zero-padded leading 8 bytes (and a content-length 1.3x
// the value the HF API metadata reported) — the Xet CAS layer was
// serving corrupt blobs, the source LFS objects need re-upload.
//
// Run: `dart run scripts/verify_hf_gguf_magic.dart`
//      `--full` reads all entries (slow, ~50 HEAD + 50 ranged GETs)
//      default mode samples the BackendRepo `repoId/<baseName>.gguf`
//      pattern only (~30 GETs).
//
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

const _gguf = [0x47, 0x47, 0x55, 0x46]; // "GGUF"
const _ggml = [0x67, 0x67, 0x6d, 0x6c]; // "ggml"

class _Probe {
  _Probe(this.url, this.expectedSize);
  final String url;
  final int? expectedSize;
}

Future<List<_Probe>> _collectUrls(bool full) async {
  final src = await File('lib/services/model_service.dart').readAsString();
  final out = <_Probe>[];
  // Grab every `url: 'https://huggingface.co/.../resolve/main/...gguf'`
  // OR `.bin` from the file.  `sizeBytes:` on the same row is the
  // local estimate — when the HEAD reveals a different value we'll
  // flag it for catalogue refresh.
  final urlRe = RegExp(
    r"url:\s*\n?\s*'(https://huggingface\.co/[^']+\.(?:gguf|bin))'",
    multiLine: true,
  );
  final sizeRe = RegExp(r'sizeBytes:\s*(\d+)(?:\s*\*\s*(\d+))?');
  for (final m in urlRe.allMatches(src)) {
    final url = m.group(1)!;
    // sizeBytes appears within ~4 lines of the url; this is a
    // heuristic — false positives just mean we won't compare sizes
    // for that entry.
    final tail = src.substring(m.end, (m.end + 200).clamp(0, src.length));
    final sm = sizeRe.firstMatch(tail);
    int? size;
    if (sm != null) {
      final a = int.tryParse(sm.group(1)!) ?? 0;
      final b = int.tryParse(sm.group(2) ?? '1') ?? 1;
      size = a * b;
      // The catalogue uses both literal byte counts AND
      // `<N> * 1024 * 1024` for MB. We can't tell which from the
      // regex alone — accept both.
    }
    out.add(_Probe(url, size));
  }
  if (!full) {
    // De-dupe by base file name — we only need to check each unique
    // blob once. Multiple catalogue rows can point at the same URL
    // (e.g. distil-large-v3 has both the f16 base entry and the
    // BackendRepo's auto-discovered siblings).
    final seen = <String>{};
    return out.where((p) => seen.add(p.url)).toList();
  }
  return out;
}

Future<void> _checkBlob(HttpClient http, _Probe probe) async {
  // Range request the first 8 bytes — much cheaper than the full
  // file and works on both HF CDN + Xet CAS layer. Some Xet
  // responses (issue #12) return zero-padded payloads even when the
  // file is range-requested, so we still catch the "starts with
  // zeros" case.
  final uri = Uri.parse(probe.url);
  try {
    final req = await http.getUrl(uri);
    req.headers.add('Range', 'bytes=0-7');
    final resp = await req.close();
    if (resp.statusCode != 206 && resp.statusCode != 200) {
      print('  [HTTP ${resp.statusCode}] ${probe.url}');
      await resp.drain<void>();
      return;
    }
    final firstBytes = <int>[];
    await for (final chunk in resp) {
      firstBytes.addAll(chunk);
      if (firstBytes.length >= 8) break;
    }
    final head = firstBytes.take(4).toList();
    final isGguf = _listEq(head, _gguf);
    final isGgml = _listEq(head, _ggml);
    if (!isGguf && !isGgml) {
      final hex = head.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      print('  [BAD MAGIC=$hex] ${probe.url}');
    } else {
      // Cross-check the content-length the server reports
      // against our catalogue sizeBytes (when we have it).
      final crange = resp.headers.value(HttpHeaders.contentRangeHeader);
      if (crange != null && probe.expectedSize != null) {
        final totalMatch = RegExp(r'/(\d+)$').firstMatch(crange);
        if (totalMatch != null) {
          final actual = int.parse(totalMatch.group(1)!);
          final expected = probe.expectedSize!;
          // Allow 10% slack — catalogue values are MB-rounded.
          if ((actual - expected).abs() > expected * 0.1) {
            print('  [SIZE MISMATCH] ${probe.url}'
                '\n      actual=$actual expected≈$expected');
            return;
          }
        }
      }
      print('  [OK] ${probe.url}');
    }
  } catch (e) {
    print('  [ERROR $e] ${probe.url}');
  }
}

bool _listEq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void main(List<String> args) async {
  final full = args.contains('--full');
  final probes = await _collectUrls(full);
  print('Verifying ${probes.length} unique blob URL(s)…');
  final http = HttpClient()..connectionTimeout = const Duration(seconds: 12);
  for (final p in probes) {
    await _checkBlob(http, p);
  }
  http.close(force: true);
}
