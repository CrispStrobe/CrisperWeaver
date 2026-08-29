// DownloadEngine — the resume protocol behind ModelService's model
// downloads (issue #35).
//
// The bug this file exists to pin down: the old implementation sent a
// `Range: bytes=N-` header and then handed the URL to `Dio.download`,
// which truncates the destination and writes the response body from
// byte 0. The server answered 206 with only the tail, so the file ended
// up *missing its first N bytes* — a plausible-looking file that then
// failed checksum verification ("Download verification failed…") or was
// rejected as short ("Download incomplete. Expected at least …").
//
// Everything here runs against a raw ServerSocket on 127.0.0.1 speaking
// HTTP/1.1 by hand, so 206 / 200 / 416 / bogus Content-Range /
// connection-dropped-mid-body are all exactly reproducible. No network
// access beyond loopback, no Flutter bindings (deliberately no
// TestWidgetsFlutterBinding: it installs HttpOverrides that would stub
// out the very HttpClient dio needs).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:crisper_weaver/services/model_service.dart';

/// Deterministic pseudo-random payload — an LCG so a wrong offset can
/// never accidentally match the expected bytes.
Uint8List _pattern(int length) {
  final out = Uint8List(length);
  var x = 0x12345678;
  for (var i = 0; i < length; i++) {
    x = (x * 1103515245 + 12345) & 0x7FFFFFFF;
    out[i] = (x >> 16) & 0xFF;
  }
  return out;
}

String _digest(List<int> bytes) => sha1.convert(bytes).toString();

/// A hand-rolled HTTP/1.1 file server with switchable misbehaviour.
class _FakeFileServer {
  _FakeFileServer(this.data);

  final Uint8List data;
  late final ServerSocket _socket;

  /// Every `Range` header we were sent, in order (null = none).
  final List<String?> rangeHeaders = <String?>[];

  /// When false the server ignores `Range` entirely and answers 200 with
  /// the whole body — what some proxies and CDNs do.
  bool honorRange = true;

  /// Replaces the `Content-Range` header on a 206 response.
  String? contentRangeOverride;

  /// When set, only this many body bytes are written before the socket
  /// is closed — a transfer that dies mid-flight.
  int? cutAfterBytes;

  /// When false no `Content-Length` is sent, so the body is delimited by
  /// EOF and the client can't tell a short body from a complete one.
  bool sendContentLength = true;

  int get port => _socket.port;
  String get url => 'http://127.0.0.1:$port/model.bin';

  Future<void> start() async {
    _socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _socket.listen(_serve);
  }

  Future<void> stop() => _socket.close();

  Future<void> _serve(Socket client) async {
    // A client that walks away mid-response (we cancel the stream when
    // we reject a Content-Range) must not surface as an unhandled error.
    client.done.catchError((Object _) {});
    try {
      final head = await _readHead(client);
      if (head == null) {
        client.destroy();
        return;
      }
      await _respond(client, head);
    } catch (_) {
      // Broken pipe / reset — expected for the aborted-response cases.
      try {
        client.destroy();
      } catch (_) {
        // Nothing to do.
      }
    }
  }

  Future<String?> _readHead(Socket client) {
    final buffer = <int>[];
    final done = Completer<String?>();
    // The subscription is deliberately never cancelled: cancelling a
    // Socket's read stream can tear the socket down before we've had a
    // chance to write the response.
    client.listen(
      (chunk) {
        if (done.isCompleted) return;
        buffer.addAll(chunk);
        final text = String.fromCharCodes(buffer);
        final idx = text.indexOf('\r\n\r\n');
        if (idx >= 0) done.complete(text.substring(0, idx));
      },
      onError: (Object _) {
        if (!done.isCompleted) done.complete(null);
      },
      onDone: () {
        if (!done.isCompleted) done.complete(null);
      },
      cancelOnError: true,
    );
    return done.future;
  }

  Future<void> _respond(Socket client, String head) async {
    String? range;
    for (final line in head.split('\r\n').skip(1)) {
      final i = line.indexOf(':');
      if (i < 0) continue;
      if (line.substring(0, i).trim().toLowerCase() == 'range') {
        range = line.substring(i + 1).trim();
      }
    }
    rangeHeaders.add(range);

    var start = 0;
    var partial = false;
    if (range != null && honorRange) {
      final m = RegExp(r'bytes=(\d+)-').firstMatch(range);
      if (m != null) {
        start = int.parse(m.group(1)!);
        partial = true;
      }
    }

    if (partial && start >= data.length) {
      client.add(utf8.encode('HTTP/1.1 416 Range Not Satisfiable\r\n'
          'Content-Range: bytes */${data.length}\r\n'
          'Content-Length: 0\r\n'
          'Connection: close\r\n\r\n'));
      await client.flush();
      await client.close();
      return;
    }

    final body = Uint8List.sublistView(data, partial ? start : 0);
    final headers = StringBuffer();
    if (partial) {
      final contentRange = contentRangeOverride ??
          'bytes $start-${data.length - 1}/${data.length}';
      headers.write('HTTP/1.1 206 Partial Content\r\n');
      headers.write('Content-Range: $contentRange\r\n');
    } else {
      headers.write('HTTP/1.1 200 OK\r\n');
    }
    headers.write('Accept-Ranges: bytes\r\n');
    headers.write('Content-Type: application/octet-stream\r\n');
    if (sendContentLength) {
      headers.write('Content-Length: ${body.length}\r\n');
    }
    headers.write('Connection: close\r\n\r\n');
    client.add(utf8.encode(headers.toString()));

    final cut = cutAfterBytes;
    if (cut != null && cut < body.length) {
      client.add(Uint8List.sublistView(body, 0, cut));
      await client.flush();
      // FIN rather than RST: the prefix stays delivered, and the client
      // sees the body end early.
      await client.close();
      return;
    }

    client.add(body);
    await client.flush();
    await client.close();
  }
}

void main() {
  const int size = 4 * 1024 * 1024;
  final data = _pattern(size);
  final fullDigest = _digest(data);

  late Directory tmp;
  late _FakeFileServer server;
  late String savePath;

  Future<void> expectComplete() async {
    final file = File(savePath);
    expect(await file.exists(), isTrue, reason: 'download file missing');
    expect(await file.length(), size, reason: 'wrong length');
    expect(_digest(await file.readAsBytes()), fullDigest,
        reason: 'file contents differ from the served bytes');
  }

  DownloadEngine engine() => DownloadEngine(Dio());

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('crisper_dl_test');
    savePath = p.join(tmp.path, 'model.bin.tmp');
    server = _FakeFileServer(data);
    await server.start();
  });

  tearDown(() async {
    await server.stop();
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  test('fresh download writes the file byte-for-byte', () async {
    // Deliberately wrong catalogue estimate: the server's Content-Length
    // is the authority, so an over-estimate must not fail the download.
    await engine().download(
      server.url,
      savePath,
      expectedSize: size + 5 * 1024 * 1024,
    );

    await expectComplete();
    expect(server.rangeHeaders, [null], reason: 'no Range on a fresh start');
  });

  test('resumes onto an existing partial when the server honours Range',
      () async {
    // The regression test for issue #35: the old Dio.download path
    // replaced the partial with the tail, producing a file missing its
    // first 1 MB that still looked about the right size.
    const partial = 1024 * 1024;
    await File(savePath).writeAsBytes(Uint8List.sublistView(data, 0, partial));

    await engine().download(server.url, savePath, expectedSize: size);

    await expectComplete();
    expect(server.rangeHeaders, ['bytes=$partial-']);
  });

  test('restarts from scratch when the server ignores Range (200)', () async {
    const partial = 512 * 1024;
    await File(savePath).writeAsBytes(Uint8List.sublistView(data, 0, partial));
    server.honorRange = false;

    await engine().download(server.url, savePath, expectedSize: size);

    // Whole body written from offset 0 — the partial must have been
    // truncated away, not appended to.
    await expectComplete();
    expect(server.rangeHeaders, ['bytes=$partial-']);
  });

  test('a dropped connection keeps the partial, and the retry resumes',
      () async {
    const cut = 900 * 1024;
    server.cutAfterBytes = cut;

    await expectLater(
      engine().download(server.url, savePath, expectedSize: size),
      throwsA(anything),
    );

    final kept = await File(savePath).length();
    expect(kept, greaterThan(0), reason: 'partial was deleted — no resume');
    expect(kept, lessThan(size));
    expect(_digest(await File(savePath).readAsBytes()),
        _digest(Uint8List.sublistView(data, 0, kept)),
        reason: 'the kept prefix must be the real first $kept bytes');

    // Second call: server behaves, download resumes from where it died.
    server.cutAfterBytes = null;
    await engine().download(server.url, savePath, expectedSize: size);

    await expectComplete();
    expect(server.rangeHeaders.length, 2);
    expect(server.rangeHeaders.first, isNull);
    expect(server.rangeHeaders.last, 'bytes=$kept-');
  });

  test('a Content-Range that does not match our offset restarts the download',
      () async {
    const partial = 700 * 1024;
    await File(savePath).writeAsBytes(Uint8List.sublistView(data, 0, partial));
    // Server claims it is sending from byte 0 while our partial is at
    // 700 KB: appending would corrupt the file.
    server.contentRangeOverride = 'bytes 0-${size - 1}/$size';

    await engine().download(server.url, savePath, expectedSize: size);

    await expectComplete();
    expect(server.rangeHeaders.length, 2, reason: 'expected one retry');
    expect(server.rangeHeaders.first, 'bytes=$partial-');
    expect(server.rangeHeaders.last, isNull,
        reason: 'the retry must not send a Range header');
  });

  test('a complete partial answered with 416 is accepted as-is', () async {
    await File(savePath).writeAsBytes(data);

    await engine().download(server.url, savePath, expectedSize: size);

    await expectComplete();
    expect(server.rangeHeaders, ['bytes=$size-']);
  });

  test('a short body with no Content-Length throws but keeps the partial',
      () async {
    // No Content-Length means EOF ends the body, so the shortfall is
    // only detectable against the catalogue estimate — the fallback
    // tolerance path. The partial must survive for a later resume.
    server.sendContentLength = false;
    server.cutAfterBytes = 1024 * 1024;

    await expectLater(
      engine().download(server.url, savePath, expectedSize: size),
      throwsA(isA<ResumableDownloadException>()),
    );

    expect(await File(savePath).length(), 1024 * 1024);

    server.sendContentLength = true;
    server.cutAfterBytes = null;
    await engine().download(server.url, savePath, expectedSize: size);
    await expectComplete();
  });
}
