import 'dart:convert';
import 'package:http/http.dart' as http;

/// Nominatim（OpenStreetMap）を使用した無料のジオコーディングサービス
class GeocodingService {
  static const String _baseUrl = 'https://nominatim.openstreetmap.org';
  static const String _userAgent = 'MonocLocSaver/1.0';

  /// 座標から住所・地点情報を取得（逆ジオコーディング）
  static Future<PlaceInfo?> reverseGeocode(double lat, double lon) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/reverse?format=jsonv2&lat=$lat&lon=$lon&zoom=18&addressdetails=1&extratags=1&namedetails=1',
      );

      final response = await http.get(
        url,
        headers: {'User-Agent': _userAgent},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return PlaceInfo.fromNominatim(data);
      }
    } catch (e) {
      print('Geocoding error: $e');
    }
    return null;
  }

  /// 道路情報を取得
  static Future<RoadInfo?> getRoadInfo(double lat, double lon) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/reverse?format=jsonv2&lat=$lat&lon=$lon&zoom=17&addressdetails=1',
      );

      final response = await http.get(
        url,
        headers: {'User-Agent': _userAgent},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return RoadInfo.fromNominatim(data);
      }
    } catch (e) {
      print('Road info error: $e');
    }
    return null;
  }
}

/// 地点情報
class PlaceInfo {
  final String? name; // 施設名・地点名
  final String? type; // 場所の種類（restaurant, station, etc.）
  final String? road; // 道路名
  final String? neighbourhood; // 近隣地区
  final String? suburb; // 地区
  final String? city; // 市区町村
  final String? state; // 都道府県
  final String? country; // 国
  final String? postcode; // 郵便番号
  final String? displayName; // 完全な住所
  final Map<String, String>? extratags; // 追加情報（営業時間、電話番号など）
  final String? category; // カテゴリ

  PlaceInfo({
    this.name,
    this.type,
    this.road,
    this.neighbourhood,
    this.suburb,
    this.city,
    this.state,
    this.country,
    this.postcode,
    this.displayName,
    this.extratags,
    this.category,
  });

  factory PlaceInfo.fromNominatim(Map<String, dynamic> data) {
    final address = data['address'] as Map<String, dynamic>? ?? {};
    final extratags = data['extratags'] as Map<String, dynamic>?;
    final namedetails = data['namedetails'] as Map<String, dynamic>?;

    // 施設名を取得（優先順位: namedetails > name > amenity名など）
    String? name = namedetails?['name'] ?? data['name'];
    if (name == null || name.isEmpty) {
      // 施設タイプから名前を推測
      name = address['amenity'] ??
          address['shop'] ??
          address['tourism'] ??
          address['leisure'] ??
          address['building'];
    }

    return PlaceInfo(
      name: name,
      type: data['type'],
      road: address['road'],
      neighbourhood: address['neighbourhood'],
      suburb: address['suburb'] ?? address['quarter'] ?? address['residential'],
      city: address['city'] ?? address['town'] ?? address['village'] ?? address['municipality'],
      state: address['state'] ?? address['province'],
      country: address['country'],
      postcode: address['postcode'],
      displayName: data['display_name'],
      extratags: extratags?.map((k, v) => MapEntry(k, v.toString())),
      category: data['category'],
    );
  }

  /// 短い表示名を生成
  String get shortName {
    if (name != null && name!.isNotEmpty) return name!;
    if (road != null) return road!;
    if (suburb != null) return suburb!;
    if (city != null) return city!;
    return '不明な場所';
  }

  /// 中程度の詳細な住所
  String get mediumAddress {
    final parts = <String>[];
    if (suburb != null) parts.add(suburb!);
    if (city != null) parts.add(city!);
    return parts.isEmpty ? shortName : parts.join(', ');
  }

  /// 完全な住所
  String? get address {
    if (displayName != null) return displayName;
    final parts = <String>[];
    if (road != null) parts.add(road!);
    if (suburb != null) parts.add(suburb!);
    if (city != null) parts.add(city!);
    if (state != null) parts.add(state!);
    return parts.isEmpty ? null : parts.join(', ');
  }

  /// 場所の種類を日本語で
  String get typeLabel {
    switch (category) {
      case 'amenity':
        return _getAmenityLabel(type);
      case 'shop':
        return 'お店';
      case 'tourism':
        return '観光地';
      case 'leisure':
        return 'レジャー';
      case 'highway':
        return '道路';
      case 'railway':
        return '鉄道';
      default:
        return type ?? '';
    }
  }

  String _getAmenityLabel(String? type) {
    switch (type) {
      case 'restaurant':
        return 'レストラン';
      case 'cafe':
        return 'カフェ';
      case 'fast_food':
        return 'ファストフード';
      case 'bar':
        return 'バー';
      case 'bank':
        return '銀行';
      case 'hospital':
        return '病院';
      case 'pharmacy':
        return '薬局';
      case 'school':
        return '学校';
      case 'university':
        return '大学';
      case 'library':
        return '図書館';
      case 'parking':
        return '駐車場';
      case 'fuel':
        return 'ガソリンスタンド';
      case 'post_office':
        return '郵便局';
      case 'police':
        return '警察署';
      case 'fire_station':
        return '消防署';
      case 'place_of_worship':
        return '宗教施設';
      default:
        return type ?? '施設';
    }
  }
}

/// 道路情報
class RoadInfo {
  final String? roadName;
  final String? roadType; // motorway, trunk, primary, secondary, etc.
  final bool isHighway; // 高速道路・有料道路
  final bool isRailway; // 鉄道

  RoadInfo({
    this.roadName,
    this.roadType,
    this.isHighway = false,
    this.isRailway = false,
  });

  factory RoadInfo.fromNominatim(Map<String, dynamic> data) {
    final category = data['category'];
    final type = data['type'];
    final address = data['address'] as Map<String, dynamic>? ?? {};

    bool isHighway = false;
    bool isRailway = false;

    if (category == 'highway') {
      // 道路種別の判定
      isHighway = type == 'motorway' ||
          type == 'motorway_link' ||
          type == 'trunk' ||
          type == 'trunk_link';
    } else if (category == 'railway') {
      isRailway = true;
    }

    return RoadInfo(
      roadName: address['road'],
      roadType: type,
      isHighway: isHighway,
      isRailway: isRailway,
    );
  }

  /// 道路種別を日本語で
  String get roadTypeLabel {
    if (isRailway) return '鉄道';
    if (isHighway) return '高速道路';

    switch (roadType) {
      case 'motorway':
      case 'motorway_link':
        return '高速道路';
      case 'trunk':
      case 'trunk_link':
        return '国道（主要）';
      case 'primary':
      case 'primary_link':
        return '国道';
      case 'secondary':
      case 'secondary_link':
        return '県道';
      case 'tertiary':
      case 'tertiary_link':
        return '市道';
      case 'residential':
        return '住宅街';
      case 'service':
        return 'サービス道路';
      case 'footway':
      case 'pedestrian':
        return '歩道';
      case 'cycleway':
        return '自転車道';
      case 'path':
        return '小道';
      default:
        return '一般道';
    }
  }
}
