import 'dart:convert';
import 'package:flutter/material.dart';

enum SurfaceType {
  glossy,
  matte,
  glitter,
  chrome,
  catEye,
  holographic,
  pearl,
  satin,
}

enum NailColorMode { solid, gradient, perFinger }

class _NailColorConfig {
  final NailColorMode mode;
  final Color primaryColor;
  final List<Color> gradientColors;
  final Map<int, Color> perFingerColors;

  const _NailColorConfig({
    required this.mode,
    required this.primaryColor,
    this.gradientColors = const [],
    this.perFingerColors = const {},
  });
}

class NailVariant {
  final int nailVariantId;
  final String name;
  final int? nailShapeId;
  final String? shapeName;
  final int? nailSurfaceId;
  final String? surfaceName;
  final int? nailDesignId;
  final double price;
  final int duration; // in minutes
  final String imageUrl;
  final String shapeImageUrl;
  final String colorJson;
  final SurfaceType surfaceType;
  final String surfaceShaderParam;
  final NailColorMode colorMode;
  final Color primaryColor;
  final Color? secondaryColor;
  final List<Color> gradientColors;
  final Map<int, Color> perFingerColors;
  final bool isRemote;

  NailVariant({
    required this.nailVariantId,
    required this.name,
    this.nailShapeId,
    this.shapeName,
    this.nailSurfaceId,
    this.surfaceName,
    this.nailDesignId,
    required this.price,
    this.duration = 45,
    this.imageUrl = '',
    this.shapeImageUrl = '',
    required this.colorJson,
    this.surfaceType = SurfaceType.glossy,
    this.surfaceShaderParam = '',
    this.colorMode = NailColorMode.solid,
    required this.primaryColor,
    this.secondaryColor,
    this.gradientColors = const [],
    this.perFingerColors = const {},
    this.isRemote = false,
  });

  factory NailVariant.fromJson(Map<String, dynamic> json, {String? baseUrl}) {
    final colorJsonStr = json['colorJson']?.toString() ?? '';
    final colorConfig = _parseColorConfig(colorJsonStr);
    final imageUrl = _resolveUrl(json['imageUrl']?.toString(), baseUrl);
    final shapeImageUrl = _resolveUrl(
      (json['nailShape']?['imageUrl'] ?? json['shapeImageUrl'])?.toString(),
      baseUrl,
    );
    final surfaceShaderParam =
        (json['nailSurface']?['shaderParam'] ?? json['shaderParam'] ?? '')
            .toString();

    final finishTypeRaw =
        (json['nailSurface']?['finishType'] ??
                surfaceShaderParam ??
                json['finishType'] ??
                json['nailSurface']?['name'] ??
                json['surfaceName'] ??
                '')
            .toString()
            .toLowerCase();

    SurfaceType parsedSurface = SurfaceType.glossy;
    if (finishTypeRaw.contains('matte') || finishTypeRaw.contains('nhám')) {
      parsedSurface = SurfaceType.matte;
    } else if (finishTypeRaw.contains('glitter') ||
        finishTypeRaw.contains('kim tuyến')) {
      parsedSurface = SurfaceType.glitter;
    } else if (finishTypeRaw.contains('chrome') ||
        finishTypeRaw.contains('tráng gương')) {
      parsedSurface = SurfaceType.chrome;
    } else if (finishTypeRaw.contains('cat-eye') ||
        finishTypeRaw.contains('cateye') ||
        finishTypeRaw.contains('cat eye') ||
        finishTypeRaw.contains('mắt mèo')) {
      parsedSurface = SurfaceType.catEye;
    } else if (finishTypeRaw.contains('holographic') ||
        finishTypeRaw.contains('hologram') ||
        finishTypeRaw.contains('holo')) {
      parsedSurface = SurfaceType.holographic;
    } else if (finishTypeRaw.contains('pearl') ||
        finishTypeRaw.contains('ngọc trai')) {
      parsedSurface = SurfaceType.pearl;
    } else if (finishTypeRaw.contains('satin') ||
        finishTypeRaw.contains('lụa')) {
      parsedSurface = SurfaceType.satin;
    }

    return NailVariant(
      nailVariantId: json['nailVariantId'] ?? 0,
      name: json['name'] ?? 'Mẫu móng nghệ thuật',
      nailShapeId: json['nailShapeId'],
      shapeName: json['nailShape']?['name'] ?? json['shapeName'] ?? 'Almond',
      nailSurfaceId: json['nailSurfaceId'],
      surfaceName:
          json['nailSurface']?['name'] ?? json['surfaceName'] ?? 'Glossy',
      nailDesignId: json['nailDesignId'],
      price: (json['price'] as num?)?.toDouble() ?? 150000.0,
      duration: json['duration'] ?? 45,
      imageUrl: imageUrl,
      shapeImageUrl: shapeImageUrl,
      colorJson: colorJsonStr,
      surfaceType: parsedSurface,
      surfaceShaderParam: surfaceShaderParam,
      colorMode: colorConfig.mode,
      primaryColor: colorConfig.primaryColor,
      gradientColors: colorConfig.gradientColors,
      perFingerColors: colorConfig.perFingerColors,
      isRemote: true,
    );
  }

  factory NailVariant.fromApiJson(
    Map<String, dynamic> json, {
    String? baseUrl,
  }) {
    final nailShape = _readMap(json, 'nailShape');
    final nailSurface = _readMap(json, 'nailSurface');
    final colorJsonStr = _readString(json, 'colorJson') ?? '';
    final colorConfig = _parseColorConfig(colorJsonStr);
    final imageUrl = _resolveUrl(_readString(json, 'imageUrl'), baseUrl);
    final shapeImageUrl = _resolveUrl(
      _readString(nailShape, 'imageUrl') ?? _readString(json, 'shapeImageUrl'),
      baseUrl,
    );
    final surfaceShaderParam =
        _readString(nailSurface, 'shaderParam') ??
        _readString(json, 'shaderParam') ??
        '';
    final finishTypeRaw = _normalizeForMatching(
      [
        _readString(nailSurface, 'finishType'),
        surfaceShaderParam,
        _readString(json, 'finishType'),
        _readString(nailSurface, 'name'),
        _readString(json, 'surfaceName'),
      ].whereType<String>().join(' '),
    );

    return NailVariant(
      nailVariantId: _readInt(json, 'nailVariantId') ?? 0,
      name: _readString(json, 'name') ?? 'Mau mong nghe thuat',
      nailShapeId: _readInt(json, 'nailShapeId'),
      shapeName:
          _readString(nailShape, 'name') ??
          _readString(json, 'shapeName') ??
          'Almond',
      nailSurfaceId: _readInt(json, 'nailSurfaceId'),
      surfaceName:
          _readString(nailSurface, 'name') ??
          _readString(json, 'surfaceName') ??
          'Glossy',
      nailDesignId: _readInt(json, 'nailDesignId'),
      price: _readDouble(json, 'price') ?? 150000.0,
      duration: _readInt(json, 'duration') ?? 45,
      imageUrl: imageUrl,
      shapeImageUrl: shapeImageUrl,
      colorJson: colorJsonStr,
      surfaceType: _parseSurfaceType(finishTypeRaw),
      surfaceShaderParam: surfaceShaderParam,
      colorMode: colorConfig.mode,
      primaryColor: colorConfig.primaryColor,
      gradientColors: colorConfig.gradientColors,
      perFingerColors: colorConfig.perFingerColors,
      isRemote: true,
    );
  }

  Color colorForFingerIndex(int fingerIndex) {
    return perFingerColors[fingerIndex] ?? primaryColor;
  }

  static _NailColorConfig _parseColorConfig(String colorJsonStr) {
    if (colorJsonStr.isEmpty) {
      return const _NailColorConfig(
        mode: NailColorMode.solid,
        primaryColor: Color(0xFFFF4081),
      );
    }

    try {
      var raw = colorJsonStr.trim();
      if (raw.startsWith('"') && raw.endsWith('"') && raw.length > 2) {
        raw = raw
            .substring(1, raw.length - 1)
            .replaceAll(r'\"', '"')
            .replaceAll('""', '"');
      }
      raw = raw.replaceAll(r'\"', '"');

      if (raw.startsWith('{') || raw.startsWith('[')) {
        final decoded = json.decode(raw);

        if (decoded is Map<String, dynamic>) {
          return _parseColorMap(decoded);
        }

        if (decoded is List && decoded.isNotEmpty) {
          final colors = decoded
              .where((color) => color != null)
              .map((color) => _parseHex(color.toString()))
              .toList();

          if (colors.isNotEmpty) {
            return _NailColorConfig(
              mode: colors.length > 1
                  ? NailColorMode.gradient
                  : NailColorMode.solid,
              primaryColor: colors.first,
              gradientColors: colors.length > 1
                  ? List.unmodifiable(colors)
                  : const [],
            );
          }
        }
      }

      final hexRegex = RegExp(r'#(?:[0-9a-fA-F]{3,4}){1,2}|0x[0-9a-fA-F]{6,8}');
      final match = hexRegex.firstMatch(raw);
      if (match != null) {
        return _NailColorConfig(
          mode: NailColorMode.solid,
          primaryColor: _parseHex(match.group(0)!),
        );
      }
    } catch (e) {
      debugPrint('Error parsing colorJson "$colorJsonStr": $e');
    }

    return const _NailColorConfig(
      mode: NailColorMode.solid,
      primaryColor: Color(0xFFFF4081),
    );
  }

  static _NailColorConfig _parseColorMap(Map<String, dynamic> decodedMap) {
    final mode = decodedMap['mode']?.toString().toLowerCase();

    if (mode == 'perfinger' && decodedMap['fingers'] is List) {
      final perFingerColors = <int, Color>{};
      for (final finger in decodedMap['fingers'] as List) {
        if (finger is! Map) continue;
        final fingerIndex = (finger['fingerIndex'] as num?)?.toInt();
        final colorRaw = finger['color']?.toString();
        if (fingerIndex == null || colorRaw == null) continue;
        perFingerColors[fingerIndex] = _parseHex(colorRaw);
      }

      if (perFingerColors.isNotEmpty) {
        return _NailColorConfig(
          mode: NailColorMode.perFinger,
          primaryColor: perFingerColors.values.first,
          perFingerColors: Map.unmodifiable(perFingerColors),
        );
      }
    }

    final gradientColors = _parseGradientColors(decodedMap);
    if (mode == 'gradient' && gradientColors.isNotEmpty) {
      return _NailColorConfig(
        mode: NailColorMode.gradient,
        primaryColor: gradientColors.first,
        gradientColors: List.unmodifiable(gradientColors),
      );
    }

    final solidColor = _parseFirstNamedColor(decodedMap);
    if (solidColor != null) {
      return _NailColorConfig(
        mode: NailColorMode.solid,
        primaryColor: solidColor,
      );
    }

    if (gradientColors.isNotEmpty) {
      return _NailColorConfig(
        mode: NailColorMode.gradient,
        primaryColor: gradientColors.first,
        gradientColors: List.unmodifiable(gradientColors),
      );
    }

    return const _NailColorConfig(
      mode: NailColorMode.solid,
      primaryColor: Color(0xFFFFD700),
    );
  }

  static Color? _parseFirstNamedColor(Map<String, dynamic> decodedMap) {
    for (final key in ['hex', 'primary', 'base', 'color']) {
      final value = decodedMap[key];
      if (value != null) return _parseHex(value.toString());
    }

    if (decodedMap['colors'] is List) {
      final colors = decodedMap['colors'] as List;
      if (colors.isNotEmpty) return _parseHex(colors.first.toString());
    }

    if (decodedMap['rgb'] is Map) {
      final rgb = decodedMap['rgb'] as Map;
      final r = (rgb['r'] as num?)?.toInt();
      final g = (rgb['g'] as num?)?.toInt();
      final b = (rgb['b'] as num?)?.toInt();
      if (r != null && g != null && b != null) {
        return Color.fromARGB(
          255,
          r.clamp(0, 255).toInt(),
          g.clamp(0, 255).toInt(),
          b.clamp(0, 255).toInt(),
        );
      }
    }

    return null;
  }

  static List<Color> _parseGradientColors(Map<String, dynamic> decodedMap) {
    final gradient = decodedMap['gradient'];
    if (gradient is! Map) return const [];

    final stops = gradient['stops'];
    if (stops is! List || stops.isEmpty) return const [];

    return stops
        .where((stop) => stop != null)
        .map((stop) => _parseHex(stop.toString()))
        .toList();
  }

  static Color _parseHex(String hexString) {
    final cleanHex = hexString
        .replaceAll('#', '')
        .replaceAll('0x', '')
        .replaceAll('0X', '');
    final buffer = StringBuffer();
    if (cleanHex.length == 6) {
      buffer.write('ff');
      buffer.write(cleanHex);
    } else if (cleanHex.length == 8) {
      buffer.write(cleanHex);
    } else if (cleanHex.length == 3) {
      buffer.write('ff');
      for (int i = 0; i < 3; i++) {
        buffer.write(cleanHex[i]);
        buffer.write(cleanHex[i]);
      }
    } else {
      return const Color(0xFFFFD700);
    }
    return Color(int.parse(buffer.toString(), radix: 16));
  }

  static SurfaceType _parseSurfaceType(String finishTypeRaw) {
    if (finishTypeRaw.contains('matte') ||
        finishTypeRaw.contains('nham') ||
        finishTypeRaw.contains('velvet') ||
        finishTypeRaw.contains('nhung')) {
      return SurfaceType.matte;
    }
    if (finishTypeRaw.contains('glitter') ||
        finishTypeRaw.contains('sparkle') ||
        finishTypeRaw.contains('kim tuyen')) {
      return SurfaceType.glitter;
    }
    if (finishTypeRaw.contains('chrome') ||
        finishTypeRaw.contains('mirror') ||
        finishTypeRaw.contains('trang guong')) {
      return SurfaceType.chrome;
    }
    if (finishTypeRaw.contains('cat-eye') ||
        finishTypeRaw.contains('cateye') ||
        finishTypeRaw.contains('cat eye') ||
        finishTypeRaw.contains('mat meo')) {
      return SurfaceType.catEye;
    }
    if (finishTypeRaw.contains('holographic') ||
        finishTypeRaw.contains('hologram') ||
        finishTypeRaw.contains('holo')) {
      return SurfaceType.holographic;
    }
    if (finishTypeRaw.contains('pearl') ||
        finishTypeRaw.contains('ngoc trai')) {
      return SurfaceType.pearl;
    }
    if (finishTypeRaw.contains('satin') ||
        finishTypeRaw.contains('lua') ||
        finishTypeRaw.contains('silk')) {
      return SurfaceType.satin;
    }
    return SurfaceType.glossy;
  }

  static dynamic _readValue(Map<String, dynamic>? json, String key) {
    if (json == null) return null;
    if (json.containsKey(key)) return json[key];

    final targetKey = key.toLowerCase();
    for (final entry in json.entries) {
      if (entry.key.toLowerCase() == targetKey) return entry.value;
    }
    return null;
  }

  static Map<String, dynamic>? _readMap(
    Map<String, dynamic>? json,
    String key,
  ) {
    final value = _readValue(json, key);
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static String? _readString(Map<String, dynamic>? json, String key) {
    final value = _readValue(json, key);
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty) return null;

    final normalizedText = text.toLowerCase();
    if (normalizedText == 'string' ||
        normalizedText == 'null' ||
        normalizedText == 'n/a') {
      return null;
    }
    return text;
  }

  static int? _readInt(Map<String, dynamic>? json, String key) {
    final value = _readValue(json, key);
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static double? _readDouble(Map<String, dynamic>? json, String key) {
    final value = _readValue(json, key);
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static String _normalizeForMatching(String value) {
    var text = value.toLowerCase();
    const replacements = {
      'à': 'a',
      'á': 'a',
      'ạ': 'a',
      'ả': 'a',
      'ã': 'a',
      'â': 'a',
      'ầ': 'a',
      'ấ': 'a',
      'ậ': 'a',
      'ẩ': 'a',
      'ẫ': 'a',
      'ă': 'a',
      'ằ': 'a',
      'ắ': 'a',
      'ặ': 'a',
      'ẳ': 'a',
      'ẵ': 'a',
      'è': 'e',
      'é': 'e',
      'ẹ': 'e',
      'ẻ': 'e',
      'ẽ': 'e',
      'ê': 'e',
      'ề': 'e',
      'ế': 'e',
      'ệ': 'e',
      'ể': 'e',
      'ễ': 'e',
      'ì': 'i',
      'í': 'i',
      'ị': 'i',
      'ỉ': 'i',
      'ĩ': 'i',
      'ò': 'o',
      'ó': 'o',
      'ọ': 'o',
      'ỏ': 'o',
      'õ': 'o',
      'ô': 'o',
      'ồ': 'o',
      'ố': 'o',
      'ộ': 'o',
      'ổ': 'o',
      'ỗ': 'o',
      'ơ': 'o',
      'ờ': 'o',
      'ớ': 'o',
      'ợ': 'o',
      'ở': 'o',
      'ỡ': 'o',
      'ù': 'u',
      'ú': 'u',
      'ụ': 'u',
      'ủ': 'u',
      'ũ': 'u',
      'ư': 'u',
      'ừ': 'u',
      'ứ': 'u',
      'ự': 'u',
      'ử': 'u',
      'ữ': 'u',
      'ỳ': 'y',
      'ý': 'y',
      'ỵ': 'y',
      'ỷ': 'y',
      'ỹ': 'y',
      'đ': 'd',
    };

    replacements.forEach((from, to) {
      text = text.replaceAll(from, to);
    });
    return text;
  }

  static String _resolveUrl(String? rawUrl, String? baseUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) return '';
    final value = rawUrl.trim();
    final normalizedValue = value.toLowerCase();
    if (normalizedValue == 'string' ||
        normalizedValue == 'null' ||
        normalizedValue == 'n/a') {
      return '';
    }
    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme) return value;
    if (baseUrl == null || baseUrl.isEmpty) return value;

    var normalizedBase = baseUrl;
    while (normalizedBase.endsWith('/')) {
      normalizedBase = normalizedBase.substring(0, normalizedBase.length - 1);
    }
    return value.startsWith('/')
        ? '$normalizedBase$value'
        : '$normalizedBase/$value';
  }
}
