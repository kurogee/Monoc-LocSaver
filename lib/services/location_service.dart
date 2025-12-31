import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:monoc_locsaver/models/location_record.dart';
import 'package:monoc_locsaver/services/database_helper.dart';
import 'package:monoc_locsaver/services/transport_detector.dart';
import 'package:monoc_locsaver/services/geocoding_service.dart';
import 'package:monoc_locsaver/services/photo_watcher_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocationService {
  static const notificationChannelId = 'my_foreground';
  static const notificationId = 888;

  // 省電力設定
  static const int movingIntervalSeconds = 10; // 移動中は10秒間隔
  static const int stationaryIntervalSeconds = 60; // 静止時は60秒間隔
  static const int distanceFilterMeters = 10; // 10m以上移動したら記録

  Future<void> initialize() async {
    final service = FlutterBackgroundService();

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      notificationChannelId,
      'MY FOREGROUND SERVICE',
      description: 'This channel is used for important notifications.',
      importance: Importance.low,
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    if (Platform.isIOS || Platform.isAndroid) {
      await flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);
    }

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: notificationChannelId,
        initialNotificationTitle: 'Monoc LocSaver',
        initialNotificationContent: '位置情報を記録中...',
        foregroundServiceNotificationId: notificationId,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  Future<bool> requestPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }
    
    if (permission == LocationPermission.whileInUse) {
       // バックグラウンド権限が必要な場合はここで処理を追加
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  Future<void> startTracking() async {
    final service = FlutterBackgroundService();
    if (!await service.isRunning()) {
      service.startService();
    }
  }

  Future<void> stopTracking() async {
    final service = FlutterBackgroundService();
    service.invoke("stopService");
  }

  Future<Position?> getCurrentLocation() async {
    try {
      return await Geolocator.getCurrentPosition();
    } catch (e) {
      return null;
    }
  }
  
  Future<bool> isRunning() async {
    final service = FlutterBackgroundService();
    return await service.isRunning();
  }
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    // 写真監視を停止
    PhotoWatcherService.instance.stopWatching();
    service.stopSelf();
  });

  // 写真の自動同期を開始
  PhotoWatcherService.instance.startWatching();

  // 最後の位置情報と移動状態を追跡
  Position? lastPosition;
  String currentTransportMode = 'stationary';
  int consecutiveStationaryCount = 0;

  // ジオコーディングのキャッシュ（APIリクエスト削減のため）
  PlaceInfo? lastPlaceInfo;
  RoadInfo? lastRoadInfo;
  DateTime? lastGeocodingTime;
  const int geocodingCooldownSeconds = 30; // 30秒に1回のみジオコーディング

  // 省電力のための動的インターバル
  Timer? locationTimer;

  void scheduleNextUpdate(int intervalSeconds) {
    locationTimer?.cancel();
    locationTimer = Timer(Duration(seconds: intervalSeconds), () async {
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );

        // ジオコーディング（クールダウン期間を設けてAPI負荷軽減）
        final now = DateTime.now();
        bool shouldGeocode = lastGeocodingTime == null ||
            now.difference(lastGeocodingTime!).inSeconds >= geocodingCooldownSeconds;

        if (shouldGeocode) {
          try {
            // 地点情報と道路情報を並行取得
            final futures = await Future.wait([
              GeocodingService.reverseGeocode(position.latitude, position.longitude),
              GeocodingService.getRoadInfo(position.latitude, position.longitude),
            ]);
            lastPlaceInfo = futures[0] as PlaceInfo?;
            lastRoadInfo = futures[1] as RoadInfo?;
            lastGeocodingTime = now;
          } catch (e) {
            print("Geocoding Error: $e");
            // エラー時は既存のキャッシュを使用
          }
        }

        // 移動手段を判定（道路情報を考慮）
        final speed = position.speed >= 0 ? position.speed : 0.0;
        final transportMode = TransportDetector.detectTransportMode(
          speed,
          isHighway: lastRoadInfo?.isHighway,
          isRailway: lastRoadInfo?.isRailway,
          roadType: lastRoadInfo?.roadType,
        );

        // 前回の位置との距離を計算
        double distance = 0;
        if (lastPosition != null) {
          distance = TransportDetector.calculateDistance(
            lastPosition!.latitude,
            lastPosition!.longitude,
            position.latitude,
            position.longitude,
          );
        }

        // 静止状態のカウント
        if (transportMode == 'stationary') {
          consecutiveStationaryCount++;
        } else {
          consecutiveStationaryCount = 0;
        }

        // 記録するかどうかの判定
        // - 10m以上移動した場合
        // - 移動手段が変わった場合
        // - 静止状態が続いている場合は間引く
        bool shouldRecord = false;
        if (lastPosition == null) {
          shouldRecord = true;
        } else if (distance >= LocationService.distanceFilterMeters) {
          shouldRecord = true;
        } else if (transportMode != currentTransportMode) {
          shouldRecord = true;
        } else if (transportMode == 'stationary' && consecutiveStationaryCount <= 1) {
          shouldRecord = true;
        }

        if (shouldRecord) {
          final record = LocationRecord(
            latitude: position.latitude,
            longitude: position.longitude,
            timestamp: DateTime.now(),
            speed: speed,
            accuracy: position.accuracy,
            transportMode: transportMode,
            isStayPoint: transportMode == 'stationary',
            // 地点情報
            placeName: lastPlaceInfo?.name,
            placeType: lastPlaceInfo?.type,
            address: lastPlaceInfo?.address,
            // 道路情報
            roadType: lastRoadInfo?.roadType,
            isHighway: lastRoadInfo?.isHighway,
            isRailway: lastRoadInfo?.isRailway,
          );
          await DatabaseHelper.instance.create(record);
        }

        // 通知を更新
        if (service is AndroidServiceInstance) {
          final label = TransportDetector.getTransportLabel(transportMode);
          final placeName = lastPlaceInfo?.name ?? '';
          final displayText = placeName.isNotEmpty 
              ? "$label: $placeName" 
              : "$label: ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}";
          service.setForegroundNotificationInfo(
            title: "Monoc LocSaver",
            content: displayText,
          );
        }

        // UIへ更新を通知
        service.invoke(
          'update',
          {
            "lat": position.latitude,
            "lng": position.longitude,
            "speed": speed,
            "transport": transportMode,
            "placeName": lastPlaceInfo?.name,
            "placeType": lastPlaceInfo?.type,
            "address": lastPlaceInfo?.address,
            "roadType": lastRoadInfo?.roadType,
            "isHighway": lastRoadInfo?.isHighway,
            "isRailway": lastRoadInfo?.isRailway,
          },
        );

        lastPosition = position;
        currentTransportMode = transportMode;

        // 次の更新をスケジュール（移動中は高頻度、静止中は低頻度）
        final nextInterval = transportMode == 'stationary'
            ? LocationService.stationaryIntervalSeconds
            : LocationService.movingIntervalSeconds;
        scheduleNextUpdate(nextInterval);
      } catch (e) {
        print("Location Error: $e");
        // エラー時は60秒後にリトライ
        scheduleNextUpdate(60);
      }
    });
  }

  // 初回の位置取得を開始
  scheduleNextUpdate(1);
}
