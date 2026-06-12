// Web implementation of CrispEmbed — runs text embeddings client-side
// via the CrispEmbed WASM module (crispembed_embed.js + .wasm).
//
// Replaces crispembed_stub.dart on web via the conditional export in
// crispembed_import.dart. The WASM module must be loaded via a <script>
// tag in web/index.html before this code runs.

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import '../services/log_service.dart';

// ---------------------------------------------------------------------------
// CrispEmbed — web WASM implementation
// ---------------------------------------------------------------------------

class CrispEmbed {
  late final JSObject _module;
  late final int _ctxPtr;
  late final int _dim;
  bool _disposed = false;

  CrispEmbed._({
    required JSObject module,
    required int ctxPtr,
    required int dim,
  }) {
    _module = module;
    _ctxPtr = ctxPtr;
    _dim = dim;
  }

  /// Matches the native constructor signature. On web, direct construction
  /// is not supported — use [CrispEmbed.load] instead.
  CrispEmbed(String modelPath,
      {int nThreads = 0, String? libPath, bool? autoDownload}) {
    throw UnsupportedError(
        'CrispEmbed direct constructor not available on web. Use CrispEmbed.load()');
  }

  /// Load the WASM module, fetch the model, and initialize.
  static Future<CrispEmbed> load({
    String modelUrl =
        'https://huggingface.co/cstr/all-MiniLM-L6-v2-GGUF/resolve/main/all-MiniLM-L6-v2-q4_k.gguf',
    String modelPath = '/models/all-MiniLM-L6-v2-q4_k.gguf',
    int nThreads = 1,
    void Function(double)? onProgress,
  }) async {
    onProgress?.call(0.0);

    // 1. Initialize the Emscripten module
    Log.instance.i('crispembed-web', 'initializing WASM module...');
    final factory = globalContext.getProperty('CrispEmbedText'.toJS) as JSFunction;
    final modulePromise = factory.callAsFunction(null, JSObject()) as JSPromise;
    final module = (await modulePromise.toDart) as JSObject;
    Log.instance.i('crispembed-web', 'WASM module ready');
    onProgress?.call(0.1);

    // 2. Create /models directory in MEMFS
    final fs = module.getProperty('FS'.toJS) as JSObject;
    try {
      fs.callMethod('mkdir'.toJS, '/models'.toJS);
    } catch (_) {
      // Directory may already exist
    }

    // 3. Fetch the model file with progress
    Log.instance.i('crispembed-web', 'fetching model from $modelUrl');
    final response = await _jsFetch(modelUrl);
    final contentLength = _getContentLength(response);

    final body = (response.getProperty('body'.toJS) as JSObject);
    final reader = body.callMethod('getReader'.toJS) as JSObject;
    final chunks = <Uint8List>[];
    var received = 0;

    while (true) {
      final result = (await (reader.callMethod('read'.toJS) as JSPromise).toDart) as JSObject;
      final done = (result.getProperty('done'.toJS) as JSBoolean).toDart;
      if (done) break;
      final chunk = (result.getProperty('value'.toJS) as JSUint8Array).toDart;
      chunks.add(chunk);
      received += chunk.length;
      if (contentLength > 0) {
        onProgress?.call(0.1 + 0.7 * (received / contentLength));
      }
    }

    // Concatenate chunks
    final allBytes = Uint8List(received);
    var offset = 0;
    for (final chunk in chunks) {
      allBytes.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    Log.instance.i('crispembed-web', 'model downloaded: $received bytes');

    // 4. Write to MEMFS
    fs.callMethod('writeFile'.toJS, modelPath.toJS, allBytes.toJS);
    onProgress?.call(0.85);

    // 5. Initialize the embedding context via ccall
    Log.instance.i('crispembed-web', 'loading model...');
    final ctxPtr = (_ccall(module, 'wasm_embed_init', 'number',
        ['string', 'number'], [modelPath, nThreads]) as num).toInt();
    if (ctxPtr == 0) {
      throw Exception('wasm_embed_init failed — model may be corrupt');
    }

    // 6. Get dimension
    final dim = (_ccall(module, 'wasm_embed_dim', 'number', ['number'], [ctxPtr]) as num).toInt();
    Log.instance.i('crispembed-web', 'model loaded, dim=$dim');
    onProgress?.call(1.0);

    return CrispEmbed._(module: module, ctxPtr: ctxPtr, dim: dim);
  }

  // -- Public API (matches crispembed_stub.dart surface) --------------------

  bool get hasAudio => false;
  bool get hasVision => false;
  int get dim => _dim;

  Float32List encode(String text) {
    if (_disposed) throw StateError('CrispEmbed already disposed');

    // Allocate 4 bytes for the out_n_dim int parameter
    final dimPtr = _callMalloc(_module, 4);
    try {
      // Call wasm_embed_encode_copy which returns a malloc'd float array
      final resultPtr = _ccall(_module, 'wasm_embed_encode_copy', 'number',
          ['number', 'string', 'number'], [_ctxPtr, text, dimPtr]) as int;

      if (resultPtr == 0) return Float32List(0);

      // Copy from WASM HEAPF32 into a Dart Float32List
      final heapF32 = _module.getProperty('HEAPF32'.toJS) as JSObject;
      final buffer = (heapF32.getProperty('buffer'.toJS) as JSArrayBuffer);
      final wasmF32 = Float32List.view(buffer.toDart, resultPtr, _dim);
      final result = Float32List.fromList(wasmF32);

      // Free the malloc'd buffer
      _callFree(_module, resultPtr);
      return result;
    } finally {
      _callFree(_module, dimPtr);
    }
  }

  List<Float32List> encodeBatch(List<String> texts) {
    return texts.map(encode).toList();
  }

  Float32List encodeAudio(Float32List pcm) => Float32List(0);

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    try {
      _ccall(_module, 'wasm_embed_free', null, ['number'], [_ctxPtr]);
    } catch (e) {
      Log.instance.w('crispembed-web', 'dispose error: $e');
    }
  }

  // -- JS helpers -----------------------------------------------------------

  static Future<JSObject> _jsFetch(String url) async {
    final fetchFn = globalContext.getProperty('fetch'.toJS) as JSFunction;
    final promise = fetchFn.callAsFunction(null, url.toJS) as JSPromise;
    return (await promise.toDart) as JSObject;
  }

  static int _getContentLength(JSObject response) {
    final headers = response.getProperty('headers'.toJS) as JSObject;
    final cl = headers.callMethod('get'.toJS, 'content-length'.toJS);
    if (cl == null || cl.isUndefinedOrNull) return 0;
    return int.tryParse((cl as JSString).toDart) ?? 0;
  }

  /// Call a C function via Module.ccall.
  static dynamic _ccall(JSObject module, String name, String? returnType,
      List<String> argTypes, List<dynamic> args) {
    final ccallFn = module.getProperty('ccall'.toJS) as JSFunction;
    final result = ccallFn.callAsFunction(
      null,
      name.toJS,
      returnType?.toJS ?? ''.toJS,
      argTypes.map((t) => t.toJS).toList().toJS,
      args.map((a) {
        if (a is int) return a.toJS;
        if (a is String) return a.toJS;
        if (a is double) return a.toJS;
        return a as JSAny;
      }).toList().toJS,
    );
    if (returnType == 'number' && result != null) {
      return (result as JSNumber).toDartInt;
    }
    if (returnType == 'string' && result != null) {
      return (result as JSString).toDart;
    }
    return result;
  }

  static int _callMalloc(JSObject module, int size) {
    final mallocFn = module.getProperty('_malloc'.toJS) as JSFunction;
    return (mallocFn.callAsFunction(null, size.toJS) as JSNumber).toDartInt;
  }

  static void _callFree(JSObject module, int ptr) {
    final freeFn = module.getProperty('_free'.toJS) as JSFunction;
    freeFn.callAsFunction(null, ptr.toJS);
  }
}
