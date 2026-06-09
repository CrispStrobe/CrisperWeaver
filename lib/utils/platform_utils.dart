// Web-safe platform detection. On web, `dart:io` Platform throws
// UnsupportedError for every property. This file re-exports the same
// booleans but returns `false` on web instead of crashing.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' as io;

bool get isWeb => kIsWeb;
bool get isAndroid => !kIsWeb && io.Platform.isAndroid;
bool get isIOS => !kIsWeb && io.Platform.isIOS;
bool get isMacOS => !kIsWeb && io.Platform.isMacOS;
bool get isLinux => !kIsWeb && io.Platform.isLinux;
bool get isWindows => !kIsWeb && io.Platform.isWindows;
bool get isDesktop => !kIsWeb && (io.Platform.isMacOS || io.Platform.isLinux || io.Platform.isWindows);
bool get isMobile => !kIsWeb && (io.Platform.isIOS || io.Platform.isAndroid);

String get operatingSystem => kIsWeb ? 'web' : io.Platform.operatingSystem;
String get operatingSystemVersion => kIsWeb ? '' : io.Platform.operatingSystemVersion;
String get localeName => kIsWeb ? 'en' : io.Platform.localeName;
int get numberOfProcessors => kIsWeb ? 1 : io.Platform.numberOfProcessors;
String get dartVersion => kIsWeb ? 'web' : io.Platform.version;
