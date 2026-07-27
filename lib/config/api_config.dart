import 'package:flutter/foundation.dart';

class ApiConfig {
  /// Default backend port for local development
  static const int defaultPort = 5004;

  /// Custom overridden host or IP address (e.g. '192.168.1.100')
  static String? customHost;

  /// Default production API base URL
  static const String _defaultProductionUrl = 'https://nailify.onrender.com';

  /// Full backend URL passed at run time:
  /// flutter run --dart-define=NAILIFY_API_BASE_URL=https://nailify.onrender.com
  static const String apiBaseUrlFromEnv = String.fromEnvironment(
    'NAILIFY_API_BASE_URL',
  );

  /// Get active base URL depending on platform
  static String get baseUrl {
    if (apiBaseUrlFromEnv.isNotEmpty) {
      return _stripTrailingSlash(apiBaseUrlFromEnv);
    }
    if (customHost != null && customHost!.isNotEmpty) {
      return 'http://$customHost:$defaultPort';
    }

    // Default to Render production server
    return _defaultProductionUrl;
  }

  /// Endpoint paths
  static String get nailVariantsEndpoint => '$baseUrl/api/NailVariants';

  static String nailVariantDetailEndpoint(int id) =>
      '$baseUrl/api/NailVariants/$id';

  static String capableNailVariantsEndpoint(String artistId) =>
      '$baseUrl/api/NailVariants/capable-by-artist/$artistId';

  static String resolveMediaUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) return '';
    final value = rawUrl.trim();
    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme) return value;
    return value.startsWith('/') ? '$baseUrl$value' : '$baseUrl/$value';
  }

  static String _stripTrailingSlash(String value) {
    var normalized = value.trim();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }
}