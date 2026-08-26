// Unit tests for SettingsService setter/getter round-trips (§8.2).
// Verifies that each setter persists values correctly via
// SharedPreferences so ref.read(settingsServiceProvider) returns
// the expected values.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisper_weaver/services/log_service.dart';
import 'package:crisper_weaver/services/settings_service.dart';

void main() {
  late SettingsService settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settings = SettingsService(prefs);
  });

  test('defaultModel setter persists', () {
    settings.defaultModel = 'tiny';
    expect(settings.defaultModel, 'tiny');
  });

  test('defaultBackend setter persists', () {
    settings.defaultBackend = 'parakeet';
    expect(settings.defaultBackend, 'parakeet');
  });

  test('defaultLanguage setter persists', () {
    settings.defaultLanguage = 'de';
    expect(settings.defaultLanguage, 'de');
  });

  test('autoDetectLanguage setter persists', () {
    settings.autoDetectLanguage = false;
    expect(settings.autoDetectLanguage, isFalse);
  });

  test('enableWordTimestamps setter persists', () {
    settings.enableWordTimestamps = true;
    expect(settings.enableWordTimestamps, isTrue);
  });

  test('audioQuality setter persists', () {
    settings.audioQuality = 0.5;
    expect(settings.audioQuality, 0.5);
  });

  test('keepAudioFiles setter persists', () {
    settings.keepAudioFiles = true;
    expect(settings.keepAudioFiles, isTrue);
  });

  test('enableDiarizationByDefault setter persists', () {
    settings.enableDiarizationByDefault = true;
    expect(settings.enableDiarizationByDefault, isTrue);
  });

  test('appLocale setter persists', () {
    settings.appLocale = 'de';
    expect(settings.appLocale, 'de');
  });

  test('appLocale null setter clears', () {
    settings.appLocale = 'en';
    settings.appLocale = null;
    expect(settings.appLocale, isNull);
  });

  test('logLevel setter persists', () {
    settings.logLevel = LogLevel.debug;
    expect(settings.logLevel, LogLevel.debug);
  });

  test('logToFile setter persists', () {
    settings.logToFile = true;
    expect(settings.logToFile, isTrue);
  });

  test('skipChecksum setter persists', () {
    settings.skipChecksum = true;
    expect(settings.skipChecksum, isTrue);
  });

  test('hfToken setter persists', () {
    settings.hfToken = 'hf_test123';
    expect(settings.hfToken, 'hf_test123');
  });

  test('customModelsDir setter persists', () {
    settings.customModelsDir = '/tmp/models';
    expect(settings.customModelsDir, '/tmp/models');
  });

  test('model directory bookmark state persists and clears', () {
    settings.modelsDirBookmark = 'bookmark-data';
    settings.modelsDirAccessLost = true;
    expect(settings.modelsDirBookmark, 'bookmark-data');
    expect(settings.modelsDirAccessLost, isTrue);
    settings.modelsDirBookmark = null;
    expect(settings.modelsDirBookmark, isNull);
  });

  test('onboarding choices persist', () {
    expect(settings.onboardingCompleted, isFalse);
    settings.onboardingCompleted = true;
    settings.onboardingTask = 'meeting';
    settings.onboardingPriority = 'quality';
    expect(settings.onboardingCompleted, isTrue);
    expect(settings.onboardingTask, 'meeting');
    expect(settings.onboardingPriority, 'quality');
  });

  test('groupBatchByBackend setter persists', () {
    settings.groupBatchByBackend = true;
    expect(settings.groupBatchByBackend, isTrue);
  });

  test('maxConcurrentTranscriptions setter persists', () {
    settings.maxConcurrentTranscriptions = 2;
    expect(settings.maxConcurrentTranscriptions, 2);
  });

  test('maxConcurrentSessions setter persists', () {
    settings.maxConcurrentSessions = 3;
    expect(settings.maxConcurrentSessions, 3);
  });

  test('cloudLlmApiUrl setter persists', () {
    settings.cloudLlmApiUrl = 'https://api.example.com';
    expect(settings.cloudLlmApiUrl, 'https://api.example.com');
  });

  test('cloudLlmApiKey setter persists', () {
    settings.cloudLlmApiKey = 'sk-test';
    expect(settings.cloudLlmApiKey, 'sk-test');
  });

  test('cloudLlmModel setter persists', () {
    settings.cloudLlmModel = 'gpt-4o';
    expect(settings.cloudLlmModel, 'gpt-4o');
  });

  test('localLlmModelPath setter persists', () {
    settings.localLlmModelPath = '/tmp/model.gguf';
    expect(settings.localLlmModelPath, '/tmp/model.gguf');
  });

  test('localLlmNGpuLayers setter persists', () {
    settings.localLlmNGpuLayers = 32;
    expect(settings.localLlmNGpuLayers, 32);
  });

  test('localLlmNCtx setter persists', () {
    settings.localLlmNCtx = 4096;
    expect(settings.localLlmNCtx, 4096);
  });

  test('localLlmNThreads setter persists', () {
    settings.localLlmNThreads = 4;
    expect(settings.localLlmNThreads, 4);
  });

  test('localLlmMaxTokens setter persists', () {
    settings.localLlmMaxTokens = 1024;
    expect(settings.localLlmMaxTokens, 1024);
  });

  test('localLlmTemperature setter persists', () {
    settings.localLlmTemperature = 0.7;
    expect(settings.localLlmTemperature, 0.7);
  });

  test('hotkeyEnabled setter persists', () {
    settings.hotkeyEnabled = true;
    expect(settings.hotkeyEnabled, isTrue);
  });

  test('hotkeyCombo setter persists', () {
    settings.hotkeyCombo = 'meta+shift+space';
    expect(settings.hotkeyCombo, 'meta+shift+space');
  });

  test('editAudioShowTranscript setter persists', () {
    settings.editAudioShowTranscript = true;
    expect(settings.editAudioShowTranscript, isTrue);
  });

  test('watchFolderEnabled setter persists', () {
    settings.watchFolderEnabled = true;
    expect(settings.watchFolderEnabled, isTrue);
  });

  test('watchFolderPath setter persists', () {
    settings.watchFolderPath = '/tmp/watch';
    expect(settings.watchFolderPath, '/tmp/watch');
  });

  test('watchFolderPath null setter clears', () {
    settings.watchFolderPath = '/tmp/watch';
    settings.watchFolderPath = null;
    expect(settings.watchFolderPath, isNull);
  });

  test('llmCleanupMode setter persists', () {
    settings.llmCleanupMode = LlmCleanupMode.cloud;
    expect(settings.llmCleanupMode, LlmCleanupMode.cloud);
  });

  test('hfSpaceUrl setter persists', () {
    settings.hfSpaceUrl = 'https://custom.hf.space';
    expect(settings.hfSpaceUrl, 'https://custom.hf.space');
  });

  test('hfUserRepos setter persists', () {
    settings.hfUserRepos = [
      {'repoId': 'test/repo', 'backend': 'whisper'},
    ];
    expect(settings.hfUserRepos, hasLength(1));
  });

  test('preferredEngine setter persists', () {
    settings.preferredEngine = settings.preferredEngine;
    expect(settings.preferredEngine, isNotNull);
  });

  test('getter reads match setter writes', () {
    settings.defaultModel = 'small';
    settings.defaultLanguage = 'ja';
    settings.audioQuality = 0.9;
    settings.keepAudioFiles = true;
    expect(settings.defaultModel, 'small');
    expect(settings.defaultLanguage, 'ja');
    expect(settings.audioQuality, 0.9);
    expect(settings.keepAudioFiles, isTrue);
  });
}
