/// Compile-time product policy. Preferences cannot enable remote AI in Lite.
class BuildFlavor {
  static const name = String.fromEnvironment('CW_FLAVOR', defaultValue: 'full');
  static const isLite = name == 'lite';
  static const appName = isLite ? 'CrisperWeaver Lite' : 'CrisperWeaver';

  /// Downloads retrieve weights for local inference; they never send user
  /// audio/text. Disable them for a build that imports models from disk only.
  static const allowModelDownloads =
      !isLite || bool.fromEnvironment('CW_LITE_DOWNLOADS', defaultValue: true);

  /// Only literal loopback addresses: no DNS, LAN hosts, or proxy endpoints.
  /// Use 127.0.0.1 rather than localhost when configuring Ollama.
  static bool isLoopbackEndpoint(Uri uri) =>
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      (uri.host == '127.0.0.1' || uri.host == '::1') &&
      uri.userInfo.isEmpty;

  static bool allowsAiEndpoint(String url) {
    if (!isLite) return true;
    final uri = Uri.tryParse(url);
    return uri != null && isLoopbackEndpoint(uri);
  }

  static bool allowsHttpModel(String model) =>
      !isLite ||
      !RegExp(r'(^|[:\-])cloud($|[:\-])', caseSensitive: false).hasMatch(model);

  static void requireRemoteAi() {
    if (isLite) {
      throw UnsupportedError('Remote AI processing is unavailable in Lite.');
    }
  }
}
