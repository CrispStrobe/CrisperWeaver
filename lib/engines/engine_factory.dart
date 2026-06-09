import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/model_service.dart';
import '../utils/platform_utils.dart' as plat;
import 'transcription_engine.dart';
import 'mock_engine.dart';
import 'crispasr_engine.dart';
import 'hfspace_engine.dart';

/// Available transcription engine types.
enum EngineType {
  mock('mock', 'Mock Engine', 'Testing engine with simulated responses'),
  crispasr('crispasr', 'CrispASR (ggml)',
      'On-device ASR via the CrispASR FFI runtime'),
  hfspace('hfspace', 'CrispASR Cloud',
      'Cloud ASR + TTS via CrispASR HF Space');

  const EngineType(this.id, this.displayName, this.description);

  final String id;
  final String displayName;
  final String description;
}

/// Factory for creating transcription engines.
class EngineFactory {
  static final Map<EngineType, TranscriptionEngine Function()> _creators = {
    EngineType.mock: () => MockEngine(),
    EngineType.crispasr: () => CrispASREngine(),
    EngineType.hfspace: () => HfSpaceEngine(),
  };

  static TranscriptionEngine create(EngineType type) {
    final creator = _creators[type];
    if (creator == null) {
      throw UnsupportedError('Engine type $type is not implemented');
    }
    return creator();
  }

  static List<EngineType> getAvailableEngines() => plat.isWeb
      ? const [EngineType.hfspace, EngineType.mock]
      : const [EngineType.crispasr, EngineType.hfspace, EngineType.mock];

  static bool isSupported(EngineType type) =>
      getAvailableEngines().contains(type);

  static EngineType getRecommendedEngine() =>
      plat.isWeb ? EngineType.hfspace : EngineType.crispasr;
}

/// Engine manager for handling engine lifecycle and selection.
class EngineManager {
  TranscriptionEngine? _currentEngine;
  EngineType? _currentEngineType;

  TranscriptionEngine? get currentEngine => _currentEngine;
  EngineType? get currentEngineType => _currentEngineType;

  bool get hasActiveEngine => _currentEngine != null;

  Future<bool> switchEngine(
    EngineType type, {
    ModelService? modelService,
    Map<String, dynamic>? config,
  }) async {
    try {
      await _currentEngine?.dispose();

      _currentEngine = EngineFactory.create(type);
      _currentEngineType = type;

      final success = await _currentEngine!
          .initialize(modelService: modelService, config: config);

      if (!success) {
        await _currentEngine?.dispose();
        _currentEngine = null;
        _currentEngineType = null;
        return false;
      }

      return true;
    } catch (e) {
      await _currentEngine?.dispose();
      _currentEngine = null;
      _currentEngineType = null;
      return false;
    }
  }

  Future<bool> initializeWithRecommended({
    ModelService? modelService,
    Map<String, dynamic>? config,
  }) async {
    final recommended = EngineFactory.getRecommendedEngine();
    return await switchEngine(recommended,
        modelService: modelService, config: config);
  }

  Future<bool> initializeWithMock({
    ModelService? modelService,
    Map<String, dynamic>? config,
  }) async {
    return await switchEngine(EngineType.mock,
        modelService: modelService, config: config);
  }

  Future<void> dispose() async {
    await _currentEngine?.dispose();
    _currentEngine = null;
    _currentEngineType = null;
  }

  List<EngineInfo> getAvailableEnginesInfo() {
    return EngineFactory.getAvailableEngines()
        .map((type) => EngineInfo(
              type: type,
              isActive: type == _currentEngineType,
              isSupported: EngineFactory.isSupported(type),
            ))
        .toList();
  }
}

/// Engine information for UI display.
class EngineInfo {
  final EngineType type;
  final bool isActive;
  final bool isSupported;

  const EngineInfo({
    required this.type,
    required this.isActive,
    required this.isSupported,
  });

  String get displayName => type.displayName;
  String get description => type.description;
  String get id => type.id;
}

/// Riverpod providers for engine management.
final engineManagerProvider =
    NotifierProvider<EngineManagerNotifier, EngineManagerState>(
        EngineManagerNotifier.new);

/// Engine manager state.
class EngineManagerState {
  final EngineManager manager;
  final EngineType? currentEngine;
  final bool isInitialized;
  final bool isInitializing;
  final String? error;

  const EngineManagerState({
    required this.manager,
    this.currentEngine,
    this.isInitialized = false,
    this.isInitializing = false,
    this.error,
  });

  EngineManagerState copyWith({
    EngineManager? manager,
    EngineType? currentEngine,
    bool? isInitialized,
    bool? isInitializing,
    String? error,
  }) {
    return EngineManagerState(
      manager: manager ?? this.manager,
      currentEngine: currentEngine ?? this.currentEngine,
      isInitialized: isInitialized ?? this.isInitialized,
      isInitializing: isInitializing ?? this.isInitializing,
      error: error,
    );
  }
}

/// Engine manager state notifier.
class EngineManagerNotifier extends Notifier<EngineManagerState> {
  @override
  EngineManagerState build() {
    final mgr = EngineManager();
    ref.onDispose(() => mgr.dispose());
    return EngineManagerState(manager: mgr);
  }

  Future<void> initializeWithMock() async {
    state = state.copyWith(isInitializing: true, error: null);

    try {
      final success = await state.manager.initializeWithMock();

      if (success) {
        state = state.copyWith(
          currentEngine: EngineType.mock,
          isInitialized: true,
          isInitializing: false,
        );
      } else {
        state = state.copyWith(
          isInitializing: false,
          error: 'Failed to initialize mock engine',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isInitializing: false,
        error: 'Error initializing mock engine: $e',
      );
    }
  }

  Future<void> switchEngine(
    EngineType type, {
    Map<String, dynamic>? config,
  }) async {
    state = state.copyWith(isInitializing: true, error: null);

    try {
      final success = await state.manager.switchEngine(type, config: config);

      if (success) {
        state = state.copyWith(
          currentEngine: type,
          isInitialized: true,
          isInitializing: false,
        );
      } else {
        state = state.copyWith(
          isInitializing: false,
          error: 'Failed to switch to $type engine',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isInitializing: false,
        error: 'Error switching to $type engine: $e',
      );
    }
  }

}
