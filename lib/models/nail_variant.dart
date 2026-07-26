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
  final String colorJson;
  final SurfaceType surfaceType;
  final Color primaryColor;
  final Color? secondaryColor;

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
    required this.colorJson,
    this.surfaceType = SurfaceType.glossy,
    required this.primaryColor,
    this.secondaryColor,
  });

  factory NailVariant.fromJson(Map<String, dynamic> json) {
    final colorHexStr = json['colorJson']?.toString() ?? '';
    final parsedColor = _parseColor(colorHexStr);

    // Extract finishType from backend entity NailSurface or surface name
    final finishTypeRaw = (json['nailSurface']?['finishType'] ??
            json['finishType'] ??
            json['nailSurface']?['name'] ??
            json['surfaceName'] ??
            '')
        .toString()
        .toLowerCase();

    SurfaceType parsedSurface = SurfaceType.glossy;
    if (finishTypeRaw.contains('matte') || finishTypeRaw.contains('nhám')) {
      parsedSurface = SurfaceType.matte;
    } else if (finishTypeRaw.contains('glitter') || finishTypeRaw.contains('kim tuyến')) {
      parsedSurface = SurfaceType.glitter;
    } else if (finishTypeRaw.contains('chrome') || finishTypeRaw.contains('tráng gương')) {
      parsedSurface = SurfaceType.chrome;
    } else if (finishTypeRaw.contains('cat-eye') || finishTypeRaw.contains('cateye') || finishTypeRaw.contains('cat eye') || finishTypeRaw.contains('mắt mèo')) {
      parsedSurface = SurfaceType.catEye;
    } else if (finishTypeRaw.contains('holographic') || finishTypeRaw.contains('hologram') || finishTypeRaw.contains('holo')) {
      parsedSurface = SurfaceType.holographic;
    } else if (finishTypeRaw.contains('pearl') || finishTypeRaw.contains('ngọc trai')) {
      parsedSurface = SurfaceType.pearl;
    } else if (finishTypeRaw.contains('satin') || finishTypeRaw.contains('lụa')) {
      parsedSurface = SurfaceType.satin;
    }

    return NailVariant(
      nailVariantId: json['nailVariantId'] ?? 0,
      name: json['name'] ?? 'Mẫu móng nghệ thuật',
      nailShapeId: json['nailShapeId'],
      shapeName: json['nailShape']?['name'] ?? json['shapeName'] ?? 'Almond',
      nailSurfaceId: json['nailSurfaceId'],
      surfaceName: json['nailSurface']?['name'] ?? json['surfaceName'] ?? 'Glossy',
      nailDesignId: json['nailDesignId'],
      price: (json['price'] as num?)?.toDouble() ?? 150000.0,
      duration: json['duration'] ?? 45,
      imageUrl: json['imageUrl'] ?? '',
      colorJson: colorHexStr,
      surfaceType: parsedSurface,
      primaryColor: parsedColor,
    );
  }

  static Color _parseColor(String colorJsonStr) {
    if (colorJsonStr.isEmpty) return const Color(0xFFFF4081);

    try {
      String raw = colorJsonStr.trim();
      // Handle escaped JSON strings like "{\"hex\":\"#006400\"}"
      if (raw.startsWith('"') && raw.endsWith('"') && raw.length > 2) {
        raw = raw.substring(1, raw.length - 1).replaceAll(r'\"', '"').replaceAll('""', '"');
      }

      if (raw.startsWith('{')) {
        final decodedMap = json.decode(raw);
        if (decodedMap is Map<String, dynamic>) {
          if (decodedMap.containsKey('hex') && decodedMap['hex'] != null) {
            return _parseHex(decodedMap['hex'].toString());
          }
          if (decodedMap.containsKey('color') && decodedMap['color'] != null) {
            return _parseHex(decodedMap['color'].toString());
          }
          if (decodedMap.containsKey('gradient') && decodedMap['gradient'] is Map) {
            final stops = decodedMap['gradient']['stops'];
            if (stops is List && stops.isNotEmpty) {
              return _parseHex(stops.first.toString());
            }
          }
        }
      }

      // Regex match for any hex color code inside string (e.g. #006400, #FF0000, 0xFF006400)
      final RegExp hexRegex = RegExp(r'#(?:[0-9a-fA-F]{3,4}){1,2}|0x[0-9a-fA-F]{6,8}');
      final match = hexRegex.firstMatch(raw);
      if (match != null) {
        return _parseHex(match.group(0)!);
      }
    } catch (e) {
      debugPrint('⚠️ Error parsing colorJson "$colorJsonStr": $e');
    }

    return const Color(0xFFFF4081);
  }

  static Color _parseHex(String hexString) {
    final cleanHex = hexString.replaceAll('#', '').replaceAll('0x', '').replaceAll('0X', '');
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
      return const Color(0xFFFF4081);
    }
    return Color(int.parse(buffer.toString(), radix: 16));
  }
}
