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

/// Result from bi-encoder reranking.
class RerankResult {
  final int index;
  final double score;
  final String? document;
  RerankResult({required this.index, required this.score, this.document});
}

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

  /// IndexedDB database name for model caching (§12.6d).
  static const _idbName = 'crispembed-models';
  static const _idbStore = 'models';

  /// Load the WASM module, fetch the model, and initialize.
  ///
  /// §12.6d: Models are cached in IndexedDB. On subsequent loads,
  /// the cached bytes are used directly, skipping the network fetch.
  static Future<CrispEmbed> load({
    String modelUrl =
        'https://huggingface.co/cstr/all-MiniLM-L6-v2-GGUF/resolve/main/all-MiniLM-L6-v2-q4_k.gguf',
    String modelPath = '/models/all-MiniLM-L6-v2-q4_k.gguf',
    int nThreads = 1,
    void Function(double)? onProgress,
    bool useCache = true,
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

    // 3. Try IndexedDB cache first (§12.6d)
    Uint8List? allBytes;
    if (useCache) {
      allBytes = await _loadFromIndexedDB(modelUrl);
      if (allBytes != null) {
        Log.instance.i('crispembed-web',
            'loaded ${allBytes.length} bytes from IndexedDB cache');
        onProgress?.call(0.8);
      }
    }

    // 4. Fetch from network if not cached
    if (allBytes == null) {
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
      allBytes = Uint8List(received);
      var offset = 0;
      for (final chunk in chunks) {
        allBytes.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
      }
      Log.instance.i('crispembed-web', 'model downloaded: $received bytes');

      // Save to IndexedDB for next time (§12.6d)
      if (useCache) {
        _saveToIndexedDB(modelUrl, allBytes).catchError((Object e) {
          Log.instance.w('crispembed-web', 'IndexedDB save failed: $e');
        });
      }
    }

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
  bool get hasSparse => false;
  bool get hasColbert => false;
  bool get isReranker => false;
  int get dim => _dim;

  // -- Config --
  void setDim(int dim) {
    // No-op on web WASM (dimension is fixed at init)
  }

  void setPrefix(String prefix) {
    // No-op on web WASM (prefix not supported)
  }

  String get ctxQueryPrefix => '';
  String get ctxPassagePrefix => '';

  // -- Sparse / ColBERT / Reranker (not available in WASM build) --
  Map<int, double> encodeSparse(String text) => const {};

  List<Float32List> encodeMultivec(String text) => const [];

  double colbertScore(Float32List queryVecs, int nQuery, Float32List docVecs,
      int nDoc, int dim) => 0.0;

  double rerank(String query, String document) =>
      throw UnsupportedError('Cross-encoder reranking not available on web');

  List<RerankResult> rerankBiencoder(String query, List<String> documents,
      {int? topN, bool returnDocuments = false}) {
    // Bi-encoder reranking can be implemented client-side via encode+cosine.
    final qVec = encode(query);
    if (qVec.isEmpty) return [];
    final scores = <RerankResult>[];
    for (var i = 0; i < documents.length; i++) {
      final dVec = encode(documents[i]);
      if (dVec.isEmpty) continue;
      var dot = 0.0;
      for (var j = 0; j < qVec.length && j < dVec.length; j++) {
        dot += qVec[j] * dVec[j];
      }
      scores.add(RerankResult(
          index: i,
          score: dot,
          document: returnDocuments ? documents[i] : null));
    }
    scores.sort((a, b) => b.score.compareTo(a.score));
    final n = topN ?? scores.length;
    return scores.take(n).toList();
  }

  // -- Vision (not available in WASM build) --
  Float32List encodeImage(Float32List pixelPatches, Int32List gridThw) =>
      Float32List(0);

  (Float32List, List<Float32List>) encodeImageRaw(
          Float32List pixelPatches, Int32List gridThw) =>
      (Float32List(0), []);

  Float32List encodeImageFile(String path) => Float32List(0);

  Float32List encodeTextWithImageFile(String text, String imagePath) =>
      Float32List(0);

  // -- LoRA hot-swap (not available in WASM build) --
  bool get hasLora => false;
  bool setLora(String? adapterName) => false;
  String get activeLora => '';
  List<String> listLora() => const [];

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

  // -- IndexedDB caching (§12.6d) ------------------------------------------

  /// Load model bytes from IndexedDB cache. Returns null if not cached.
  static Future<Uint8List?> _loadFromIndexedDB(String key) async {
    try {
      final idb = globalContext.getProperty('indexedDB'.toJS);
      if (idb == null || idb.isUndefinedOrNull) return null;

      final openReq = (idb as JSObject)
          .callMethod('open'.toJS, _idbName.toJS, 1.toJS) as JSObject;

      // Handle upgrade — create store if needed
      openReq.setProperty('onupgradeneeded'.toJS, ((JSObject event) {
        final db = (event.getProperty('target'.toJS) as JSObject)
            .getProperty('result'.toJS) as JSObject;
        try {
          db.callMethod('createObjectStore'.toJS, _idbStore.toJS);
        } catch (_) {
          // Store already exists
        }
      }).toJS);

      final db = await _idbRequest(openReq);
      final tx = (db as JSObject).callMethod(
          'transaction'.toJS, _idbStore.toJS, 'readonly'.toJS) as JSObject;
      final store =
          tx.callMethod('objectStore'.toJS, _idbStore.toJS) as JSObject;
      final getReq = store.callMethod('get'.toJS, key.toJS) as JSObject;

      final result = await _idbRequest(getReq);
      if (result == null || result.isUndefinedOrNull) return null;
      return (result as JSUint8Array).toDart;
    } catch (e) {
      Log.instance.d('crispembed-web', 'IndexedDB read failed: $e');
      return null;
    }
  }

  /// Save model bytes to IndexedDB cache.
  static Future<void> _saveToIndexedDB(String key, Uint8List bytes) async {
    try {
      final idb = globalContext.getProperty('indexedDB'.toJS);
      if (idb == null || idb.isUndefinedOrNull) return;

      final openReq = (idb as JSObject)
          .callMethod('open'.toJS, _idbName.toJS, 1.toJS) as JSObject;

      openReq.setProperty('onupgradeneeded'.toJS, ((JSObject event) {
        final db = (event.getProperty('target'.toJS) as JSObject)
            .getProperty('result'.toJS) as JSObject;
        try {
          db.callMethod('createObjectStore'.toJS, _idbStore.toJS);
        } catch (_) {}
      }).toJS);

      final db = await _idbRequest(openReq);
      final tx = (db as JSObject).callMethod(
          'transaction'.toJS, _idbStore.toJS, 'readwrite'.toJS) as JSObject;
      final store =
          tx.callMethod('objectStore'.toJS, _idbStore.toJS) as JSObject;
      store.callMethod('put'.toJS, bytes.toJS, key.toJS);

      Log.instance.i('crispembed-web',
          'cached ${bytes.length} bytes to IndexedDB');
    } catch (e) {
      Log.instance.w('crispembed-web', 'IndexedDB write failed: $e');
    }
  }

  /// Await an IndexedDB request.
  static Future<JSAny?> _idbRequest(JSObject request) {
    final completer = Completer<JSAny?>();
    request.setProperty('onsuccess'.toJS, ((JSObject event) {
      completer.complete(
          (event.getProperty('target'.toJS) as JSObject)
              .getProperty('result'.toJS));
    }).toJS);
    request.setProperty('onerror'.toJS, ((JSObject event) {
      completer.completeError('IndexedDB request failed');
    }).toJS);
    return completer.future;
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
