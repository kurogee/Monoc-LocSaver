import 'dart:math';

/// 移動手段を検出するためのユーティリティクラス
class TransportDetector {
  // 速度しきい値 (m/s)
  static const double stationaryThreshold = 0.5; // 0.5 m/s 以下 = 静止
  static const double walkingThreshold = 2.0; // 〜2 m/s = 徒歩 (約7.2 km/h)
  static const double cyclingThreshold = 8.0; // 〜8 m/s = 自転車 (約28.8 km/h)
  static const double drivingThreshold = 25.0; // 〜25 m/s = 車 (約90 km/h)
  // それ以上は電車と判定

  /// 速度と道路情報から移動手段を判定
  static String detectTransportMode(
    double speedMps, {
    bool? isHighway,
    bool? isRailway,
    String? roadType,
  }) {
    // 鉄道上にいる場合は電車
    if (isRailway == true && speedMps > stationaryThreshold) {
      return 'train';
    }

    // 高速道路上で一定速度以上なら車
    if (isHighway == true && speedMps > cyclingThreshold) {
      return 'driving';
    }

    // 速度ベースの判定
    if (speedMps < stationaryThreshold) {
      return 'stationary';
    } else if (speedMps < walkingThreshold) {
      return 'walking';
    } else if (speedMps < cyclingThreshold) {
      // 道路種別で自転車か徒歩かを補助判定
      if (roadType == 'cycleway') {
        return 'cycling';
      }
      return 'walking'; // デフォルトは徒歩（速歩き）
    } else if (speedMps < drivingThreshold) {
      // 自転車道なら自転車、それ以外は状況判断
      if (roadType == 'cycleway') {
        return 'cycling';
      }
      // 一般道で8-25 km/hは自転車の可能性が高い
      if (speedMps < 12.0) {
        return 'cycling';
      }
      return 'driving';
    } else {
      // 高速（25 m/s = 90 km/h以上）
      // 鉄道か高速道路上なら電車/車、それ以外も状況で判断
      if (isRailway == true) {
        return 'train';
      }
      if (isHighway == true || speedMps > 35.0) {
        // 126 km/h以上は電車の可能性
        return speedMps > 35.0 ? 'train' : 'driving';
      }
      return 'train'; // デフォルトは電車
    }
  }

  /// 移動手段に応じた日本語ラベル
  static String getTransportLabel(String? mode) {
    switch (mode) {
      case 'stationary':
        return '滞在';
      case 'walking':
        return '徒歩';
      case 'cycling':
        return '自転車';
      case 'driving':
        return '車';
      case 'train':
        return '電車';
      default:
        return '移動中';
    }
  }

  /// 移動手段に応じたアイコン名（Material Icons）
  static String getTransportIconName(String? mode) {
    switch (mode) {
      case 'stationary':
        return 'location_on';
      case 'walking':
        return 'directions_walk';
      case 'cycling':
        return 'directions_bike';
      case 'driving':
        return 'directions_car';
      case 'train':
        return 'train';
      default:
        return 'navigation';
    }
  }

  /// 2点間の距離を計算（メートル）
  static double calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371000; // メートル
    final double dLat = _toRadians(lat2 - lat1);
    final double dLon = _toRadians(lon2 - lon1);
    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  static double _toRadians(double degree) {
    return degree * pi / 180;
  }
}
