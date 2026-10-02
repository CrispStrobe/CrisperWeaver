import 'package:http/http.dart' as http;

import '../constants/build_flavor.dart';
import 'ai_http_client_stub.dart' if (dart.library.io) 'ai_http_client_io.dart'
    as transport;

/// Applies Lite restrictions even when callers inject a client for testing.
/// Redirects are disabled before any body can reach a different destination.
class AiHttpClient extends http.BaseClient {
  AiHttpClient({http.Client? client})
      : _inner = client ?? transport.createAiHttpClient();

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (BuildFlavor.isLite) {
      if (!BuildFlavor.isLoopbackEndpoint(request.url)) {
        throw UnsupportedError('Lite AI endpoints must use 127.0.0.1 or ::1.');
      }
      request.followRedirects = false;
    }
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
