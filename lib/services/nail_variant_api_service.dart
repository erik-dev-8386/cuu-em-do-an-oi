import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/nail_variant.dart';

class NailVariantApiService {
  /// Fetch list of NailVariants from Backend (`GET /api/NailVariants`)
  static Future<List<NailVariant>> fetchNailVariants({
    int pageNumber = 1,
    int pageSize = 10,
    int? nailDesignId,
    String? name,
  }) async {
    return fetchPagedNailVariants(
      pageNumber: pageNumber,
      pageSize: pageSize,
      nailDesignId: nailDesignId,
      name: name,
    );
  }

  /// Alias for fetchNailVariants matching API DTO specification
  static Future<List<NailVariant>> fetchPagedNailVariants({
    int pageNumber = 1,
    int pageSize = 10,
    int? nailDesignId,
    String? name,
  }) async {
    final Map<String, String> queryParams = {
      'pageNumber': pageNumber.toString(),
      'pageSize': pageSize.toString(),
    };
    if (nailDesignId != null) {
      queryParams['nailDesignId'] = nailDesignId.toString();
    }
    if (name != null && name.isNotEmpty) {
      queryParams['name'] = name;
    }

    final Uri url = Uri.parse(
      ApiConfig.nailVariantsEndpoint,
    ).replace(queryParameters: queryParams);

    try {
      debugPrint('📡 [NailVariantApiService] GET: $url');
      final response = await http.get(
        url,
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 15)); // Tăng timeout cho Render

      if (response.statusCode == 200) {
        final decoded = json.decode(utf8.decode(response.bodyBytes));
        List<dynamic> itemsJson = [];

        if (decoded is Map<String, dynamic>) {
          // Parse ApiResult<PagedList<NailVariantDto>>
          if (decoded['isSucceeded'] == true && decoded.containsKey('data')) {
            final dataObj = decoded['data'];
            if (dataObj is Map<String, dynamic> &&
                dataObj.containsKey('items')) {
              itemsJson = dataObj['items'] as List<dynamic>;
            } else if (dataObj is List) {
              itemsJson = dataObj;
            }
          } else if (decoded.containsKey('items')) {
            itemsJson = decoded['items'] as List<dynamic>;
          }
        } else if (decoded is List) {
          itemsJson = decoded;
        }

        if (itemsJson.isNotEmpty) {
          final variants = itemsJson
              .map(
                (item) => NailVariant.fromApiJson(
              item as Map<String, dynamic>,
              baseUrl: ApiConfig.baseUrl,
            ),
          )
              .toList();
          debugPrint(
            '✅ [NailVariantApiService] Successfully fetched ${variants.length} NailVariants',
          );
          return variants;
        }
      } else {
        debugPrint(
          '⚠️ [NailVariantApiService] API error HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('⚠️ [NailVariantApiService] Network exception: $e');
    }

    debugPrint(
      'ℹ️ [NailVariantApiService] Returning preset variants fallback.',
    );
    return getPresetVariants();
  }

  /// Fetch one complete variant configuration (`GET /api/NailVariants/{id}`)
  static Future<NailVariant?> fetchNailVariantById(int id) async {
    final Uri url = Uri.parse(ApiConfig.nailVariantDetailEndpoint(id));

    try {
      debugPrint('[NailVariantApiService] GET detail: $url');
      final response = await http.get(
        url,
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final decoded = json.decode(utf8.decode(response.bodyBytes));
        Map<String, dynamic>? itemJson;

        if (decoded is Map<String, dynamic>) {
          if (decoded['isSucceeded'] == true &&
              decoded['data'] is Map<String, dynamic>) {
            itemJson = decoded['data'] as Map<String, dynamic>;
          } else if (decoded.containsKey('nailVariantId')) {
            itemJson = decoded;
          }
        }

        if (itemJson != null) {
          return NailVariant.fromApiJson(itemJson, baseUrl: ApiConfig.baseUrl);
        }
      } else {
        debugPrint(
          '[NailVariantApiService] Detail API error HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('[NailVariantApiService] Error fetching variant detail: $e');
    }

    return null;
  }

  /// Fetch capable nail variants for a specific artist (`GET /api/NailVariants/capable-by-artist/{artistId}`)
  static Future<List<NailVariant>> fetchCapableVariants(String artistId) async {
    final Uri url = Uri.parse(ApiConfig.capableNailVariantsEndpoint(artistId));
    try {
      final response = await http.get(
        url,
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final decoded = json.decode(utf8.decode(response.bodyBytes));
        if (decoded is Map<String, dynamic> && decoded['data'] is List) {
          final itemsJson = decoded['data'] as List<dynamic>;
          return itemsJson
              .map(
                (item) => NailVariant.fromApiJson(
              item as Map<String, dynamic>,
              baseUrl: ApiConfig.baseUrl,
            ),
          )
              .toList();
        }
      }
    } catch (e) {
      debugPrint(
        '⚠️ [NailVariantApiService] Error fetching artist capable variants: $e',
      );
    }
    return getPresetVariants();
  }

  /// Preset fallback variants matching Nailify salon collection
  static List<NailVariant> getPresetVariants() {
    return [
      NailVariant(
        nailVariantId: 101,
        name: 'Hồng Nude Thạch (Glossy Jelly)',
        shapeName: 'Almond',
        surfaceName: 'Bóng Gel (Glossy)',
        surfaceType: SurfaceType.glossy,
        price: 150000,
        duration: 35,
        colorJson: '#FF4081',
        primaryColor: const Color(0xFFFF4081),
      ),
      NailVariant(
        nailVariantId: 102,
        name: 'Đỏ Ruby Quý Phái (Ruby Red)',
        shapeName: 'Coffin',
        surfaceName: 'Bóng Đậm (Glossy)',
        surfaceType: SurfaceType.glossy,
        price: 180000,
        duration: 40,
        colorJson: '#D50000',
        primaryColor: const Color(0xFFD50000),
      ),
      NailVariant(
        nailVariantId: 103,
        name: 'Tím Nhám Huyền Bí (Matte Purple)',
        shapeName: 'Stiletto',
        surfaceName: 'Mờ Nhám (Matte)',
        surfaceType: SurfaceType.matte,
        price: 200000,
        duration: 45,
        colorJson: '#AA00FF',
        primaryColor: const Color(0xFFAA00FF),
      ),
      NailVariant(
        nailVariantId: 104,
        name: 'Xanh Mắt Mèo 5D (Galaxy Cat-Eye)',
        shapeName: 'Square',
        surfaceName: 'Mắt Mèo (Cat Eye)',
        surfaceType: SurfaceType.catEye,
        price: 250000,
        duration: 50,
        colorJson: '#00B0FF',
        primaryColor: const Color(0xFF00B0FF),
      ),
      NailVariant(
        nailVariantId: 105,
        name: 'Cam Kim Tuyến Hoàng Hôn (Glitter)',
        shapeName: 'Oval',
        surfaceName: 'Lấp Lánh (Glitter)',
        surfaceType: SurfaceType.glitter,
        price: 220000,
        duration: 45,
        colorJson: '#FF6D00',
        primaryColor: const Color(0xFFFF6D00),
      ),
      NailVariant(
        nailVariantId: 106,
        name: 'Bạc Tráng Gương Chrome (Chrome)',
        shapeName: 'Coffin',
        surfaceName: 'Tráng Gương (Chrome)',
        surfaceType: SurfaceType.chrome,
        price: 280000,
        duration: 60,
        colorJson: '#CFD8DC',
        primaryColor: const Color(0xFFCFD8DC),
      ),
      NailVariant(
        nailVariantId: 107,
        name: 'Cầu Vồng Holographic (Holo Glam)',
        shapeName: 'Almond',
        surfaceName: 'Holographic',
        surfaceType: SurfaceType.holographic,
        price: 320000,
        duration: 60,
        colorJson: '#E040FB',
        primaryColor: const Color(0xFFE040FB),
      ),
      NailVariant(
        nailVariantId: 108,
        name: 'Trắng Ngọc Trai Ánh Kim (Pearl White)',
        shapeName: 'Oval',
        surfaceName: 'Ngọc Trai (Pearl)',
        surfaceType: SurfaceType.pearl,
        price: 260000,
        duration: 50,
        colorJson: '#F5F5F5',
        primaryColor: const Color(0xFFF5F5F5),
      ),
      NailVariant(
        nailVariantId: 109,
        name: 'Hồng Lụa Satin Mịn (Satin Silk Pink)',
        shapeName: 'Square',
        surfaceName: 'Lụa Satin (Satin)',
        surfaceType: SurfaceType.satin,
        price: 210000,
        duration: 45,
        colorJson: '#F48FB1',
        primaryColor: const Color(0xFFF48FB1),
      ),
    ];
  }
}
