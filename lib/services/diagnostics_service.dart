import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../build_info.dart';
import 'crash_breadcrumb_service.dart';
import 'log_service.dart';
import 'model_service.dart';

/// Builds a user-reviewed support report. Nothing is transmitted here: the
/// caller explicitly copies or shares the returned text or file.
class DiagnosticsService {
  DiagnosticsService._();

  static Future<String> buildReport({ModelService? modelService}) async {
    final info = await PackageInfo.fromPlatform();
    ModelStorageHealth? storage;
    if (modelService != null && !kIsWeb) {
      try {
        storage = await modelService.getStorageHealth();
      } catch (e) {
        Log.instance.d('diagnostics', 'storage probe failed', error: e);
      }
    }

    final out = StringBuffer()
      ..writeln('CrisperWeaver diagnostics')
      ..writeln('Generated: ${DateTime.now().toUtc().toIso8601String()}')
      ..writeln('App: ${info.version}+${info.buildNumber}')
      ..writeln('App revision: $kBuildGitHashFull')
      ..writeln('Build time: $kBuildTimestamp')
      ..writeln('CrispASR: $kCrispAsrVersion ($kCrispAsrRevision)')
      ..writeln('CrispEmbed: $kCrispEmbedVersion ($kCrispEmbedRevision)')
      ..writeln('glint: $kGlintVersion ($kGlintRevision)')
      ..writeln('Platform: ${kIsWeb ? 'web' : Platform.operatingSystem}')
      ..writeln(
          'Platform version: ${kIsWeb ? 'browser' : Platform.operatingSystemVersion}')
      ..writeln('Runtime: ${kIsWeb ? 'wasm/js' : Platform.version}');
    if (storage != null) {
      out
        ..writeln('Models directory: ${storage.directory}')
        ..writeln('Models used bytes: ${storage.usedBytes}')
        ..writeln('Models free bytes: ${storage.freeBytes}')
        ..writeln('Models directory custom: ${storage.isCustomDirectory}');
    }
    // The single most useful line in a report about a crash we cannot
    // reproduce: what the previous run was doing when it stopped existing.
    final crash = CrashBreadcrumb.pendingAtStartup;
    if (crash != null) {
      out
        ..writeln()
        ..writeln('PREVIOUS RUN ENDED INSIDE A NATIVE CALL')
        ..write(crash.describe());
    }
    out
      ..writeln()
      ..writeln('Recent sanitized logs:');
    final logs = Log.instance.snapshot();
    for (final entry in logs.skip(logs.length > 200 ? logs.length - 200 : 0)) {
      out.writeln(entry.format());
    }
    return sanitize(out.toString());
  }

  /// Removes local home paths and common credential shapes before diagnostic
  /// text is displayed, copied, shared, or written to a support report.
  static String sanitize(String input, {String? homeDirectory}) {
    var value = input;
    final home = homeDirectory ?? (kIsWeb ? null : _homeDirectory());
    if (home != null && home.isNotEmpty) {
      value = value.replaceAll(home, '<home>');
    }
    value = value
        .replaceAll(
          RegExp(r'authorization:\s*bearer\s+\S+', caseSensitive: false),
          'Authorization: Bearer <redacted>',
        )
        .replaceAll(
          RegExp(r'\b(?:hf|sk)-[A-Za-z0-9_-]{12,}\b'),
          '<redacted-token>',
        );
    value = value.replaceAllMapped(
      RegExp(r'([?&](?:token|key|api_key)=)[^&\s]+', caseSensitive: false),
      (match) => '${match.group(1)}<redacted>',
    );
    return value;
  }

  static String? _homeDirectory() {
    try {
      return Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'];
    } catch (_) {
      return null;
    }
  }

  static Future<File> exportReport(String report) async {
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final file = File('${dir.path}/crisperweaver-diagnostics-$stamp.txt');
    await file.writeAsString(report, flush: true);
    return file;
  }
}
