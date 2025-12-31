import 'package:monoc_locsaver/models/location_record.dart';
import 'package:monoc_locsaver/services/transport_detector.dart';

/// 滞在地点を検出するためのユーティリティクラス
class StayDetector {
  // 滞在判定のしきい値
  static const double stayRadiusMeters = 50.0; // 50m以内に留まっている
  static const int stayMinMinutes = 5; // 5分以上滞在

  /// 現在の位置が直前の滞在地点から一定範囲内かどうかを判定
  static bool isWithinStayRadius(
    double currentLat,
    double currentLon,
    double lastLat,
    double lastLon,
  ) {
    final distance = TransportDetector.calculateDistance(
      currentLat,
      currentLon,
      lastLat,
      lastLon,
    );
    return distance <= stayRadiusMeters;
  }

  /// 滞在時間を計算（分）
  static int calculateStayDuration(DateTime start, DateTime end) {
    return end.difference(start).inMinutes;
  }

  /// 記録リストから滞在地点を特定し、滞在時間を計算
  static List<LocationRecord> processStayPoints(List<LocationRecord> records) {
    if (records.isEmpty) return records;

    final processed = <LocationRecord>[];
    LocationRecord? stayStart;

    for (int i = 0; i < records.length; i++) {
      final current = records[i];

      if (stayStart == null) {
        // 滞在開始候補
        if (current.speed != null && current.speed! < TransportDetector.stationaryThreshold) {
          stayStart = current;
        } else {
          processed.add(current);
        }
      } else {
        // 滞在中かどうかを判定
        if (isWithinStayRadius(
          current.latitude,
          current.longitude,
          stayStart.latitude,
          stayStart.longitude,
        )) {
          // まだ滞在中 - 継続
          continue;
        } else {
          // 滞在終了 - 滞在時間を計算
          final duration = calculateStayDuration(
            stayStart.timestamp,
            records[i - 1].timestamp,
          );

          if (duration >= stayMinMinutes) {
            // 有効な滞在地点として記録
            processed.add(stayStart.copyWith(
              isStayPoint: true,
              stayDurationMinutes: duration,
              transportMode: 'stationary',
            ));
          } else {
            processed.add(stayStart);
          }

          // 現在の記録を追加し、新たな滞在開始候補をリセット
          stayStart = null;
          if (current.speed != null && current.speed! < TransportDetector.stationaryThreshold) {
            stayStart = current;
          } else {
            processed.add(current);
          }
        }
      }
    }

    // 最後の滞在地点を処理
    if (stayStart != null) {
      final duration = calculateStayDuration(
        stayStart.timestamp,
        records.last.timestamp,
      );
      if (duration >= stayMinMinutes) {
        processed.add(stayStart.copyWith(
          isStayPoint: true,
          stayDurationMinutes: duration,
          transportMode: 'stationary',
        ));
      } else {
        processed.add(stayStart);
      }
    }

    return processed;
  }
}
