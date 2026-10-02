import 'dart:typed_data';

class BrowserSpeechClient {
  BrowserSpeechClient(String engine, {bool allowDownloads = true});
  Future<dynamic> request(String operation, Map<String, dynamic> payload,
          {void Function(double)? onProgress}) async =>
      throw UnsupportedError('Browser speech requires a web build');
  static Future<Float32List> decode(Uint8List bytes) async =>
      throw UnsupportedError('Browser audio decoding requires a web build');
  static Future<Uint8List> fetchBytes(String url) async =>
      throw UnsupportedError('Browser audio fetching requires a web build');
  static String audioUrl(Uint8List bytes) =>
      throw UnsupportedError('Browser only');
  static void download(String url, String filename) {}
  static void revokeUrl(String url) {}
  static Future<dynamic> history(String operation,
          {String? key, String? value}) async =>
      throw UnsupportedError('Browser history requires a web build');
  void cancel() {}
  void dispose() {}
}
