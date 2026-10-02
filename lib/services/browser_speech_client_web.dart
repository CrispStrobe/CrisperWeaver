import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

class BrowserSpeechClient {
  late final JSObject _client;
  static JSObject get _bridge =>
      globalContext.getProperty('CrisperBrowserSpeech'.toJS) as JSObject;

  BrowserSpeechClient(String engine, {bool allowDownloads = true}) {
    _client = _bridge.callMethod(
        'create'.toJS, engine.toJS, allowDownloads.toJS) as JSObject;
  }

  Future<dynamic> request(String operation, Map<String, dynamic> payload,
      {void Function(double)? onProgress}) async {
    final parameters = Map<String, dynamic>.from(payload);
    for (final entry in payload.entries) {
      if (entry.value is Float32List) {
        parameters[entry.key] = (entry.value as Float32List).toJS;
      } else if (entry.value is Uint8List) {
        parameters[entry.key] = (entry.value as Uint8List).toJS;
      }
    }
    final callback = ((JSNumber value) {
      onProgress?.call(value.toDartDouble);
    }).toJS;
    final promise = _client.callMethod(
            'request'.toJS, operation.toJS, parameters.jsify(), callback)
        as JSPromise<JSAny?>;
    final result = await promise.toDart;
    if (operation == 'synthesize') {
      final object = result as JSObject;
      return {
        'audio': (object.getProperty('audio'.toJS) as JSFloat32Array).toDart,
        'sampleRate':
            (object.getProperty('sampleRate'.toJS) as JSNumber).toDartInt,
      };
    }
    return result.dartify();
  }

  static Future<Float32List> decode(Uint8List bytes) async {
    final promise = _bridge.callMethod('decode'.toJS, bytes.toJS)
        as JSPromise<JSFloat32Array>;
    return (await promise.toDart).toDart;
  }

  static Future<Uint8List> fetchBytes(String url) async {
    final promise = _bridge.callMethod('fetchBytes'.toJS, url.toJS)
        as JSPromise<JSUint8Array>;
    return (await promise.toDart).toDart;
  }

  static String audioUrl(Uint8List bytes) =>
      (_bridge.callMethod('audioUrl'.toJS, bytes.toJS) as JSString).toDart;
  static void download(String url, String filename) =>
      _bridge.callMethod('download'.toJS, url.toJS, filename.toJS);
  static void revokeUrl(String url) =>
      _bridge.callMethod('revokeUrl'.toJS, url.toJS);
  static Future<dynamic> history(String operation,
      {String? key, String? value}) async {
    final promise = _bridge.callMethod(
            'history'.toJS, operation.toJS, key?.toJS, value?.toJS)
        as JSPromise<JSAny?>;
    return (await promise.toDart).dartify();
  }

  void cancel() => _client.callMethod('cancel'.toJS);
  void dispose() => _client.callMethod('dispose'.toJS);
}
