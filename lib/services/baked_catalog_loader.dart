// Loads the baked model catalog from the JSON asset at runtime.
// Replaces the old compiled-in `baked_models_catalog.dart` — the data
// now lives in `assets/models/catalog.json`, emitted by
// `scripts/bake_models_catalog.dart`.

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'model_catalog.dart';

class BakedCatalogLoader {
  static Map<String, ModelDefinition>? _cache;

  /// Load and cache the catalog from the bundled JSON asset.
  /// Safe to call multiple times — returns the cached result after the
  /// first successful load.
  static Future<Map<String, ModelDefinition>> load() async {
    if (_cache != null) return _cache!;
    final jsonStr =
        await rootBundle.loadString('assets/models/catalog.json');
    final list =
        (jsonDecode(jsonStr) as List<dynamic>).cast<Map<String, dynamic>>();
    _cache = <String, ModelDefinition>{
      for (final item in list)
        item['name'] as String: ModelDefinition.fromJson(item),
    };
    return _cache!;
  }

  /// Synchronous access after [load] has completed.
  /// Throws [StateError] if [load] has not been called yet.
  static Map<String, ModelDefinition> get cached =>
      _cache ??
      (throw StateError('BakedCatalogLoader.load() has not been called'));

  /// Load from a raw JSON string instead of the asset bundle.
  /// Used by tests that cannot access Flutter assets.
  static Map<String, ModelDefinition> loadFromString(String jsonStr) {
    final list =
        (jsonDecode(jsonStr) as List<dynamic>).cast<Map<String, dynamic>>();
    _cache = <String, ModelDefinition>{
      for (final item in list)
        item['name'] as String: ModelDefinition.fromJson(item),
    };
    return _cache!;
  }

  /// Clear the cache (for testing).
  static void reset() => _cache = null;
}
