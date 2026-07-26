import 'dart:io';
import 'package:flutter/foundation.dart';

class ApiConfig {
  /// Default backend port for Nailify .NET Core BE
  static const int defaultPort = 5004;

  /// Custom overridden host or IP address (e.g. '192.168.1.100')
  static String? customHost;

  /// Get active base URL depending on platform
  static String get baseUrl {
    if (customHost != null && customHost!.isNotEmpty) {
      return 'http://$customHost:$defaultPort';
    }
    if (!kIsWeb && Platform.isAndroid) {
      // Android Emulator host loopback address
      return 'http://10.0.2.2:$defaultPort';
    }
    return 'http://localhost:$defaultPort';
  }

  /// Endpoint paths
  static String get nailVariantsEndpoint => '$baseUrl/api/NailVariants';
  static String capableNailVariantsEndpoint(String artistId) =>
      '$baseUrl/api/NailVariants/capable-by-artist/$artistId';
}
