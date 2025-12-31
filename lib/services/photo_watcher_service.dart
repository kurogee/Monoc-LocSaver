import 'dart:async';
import 'dart:io';
import 'package:photo_manager/photo_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:monoc_locsaver/models/location_record.dart';
import 'package:monoc_locsaver/services/database_helper.dart';
import 'package:monoc_locsaver/services/geocoding_service.dart';

/// 写真を自動的に監視・取得するサービス
class PhotoWatcherService {
  static final PhotoWatcherService _instance = PhotoWatcherService._internal();
  static PhotoWatcherService get instance => _instance;
  PhotoWatcherService._internal();

  static const String _lastSyncKey = 'last_photo_sync_time';
  Timer? _watchTimer;
  bool _isWatching = false;

  /// 写真アクセス権限をリクエスト
  Future<bool> requestPermission() async {
    final permission = await PhotoManager.requestPermissionExtend();
    return permission.isAuth;
  }

  /// 写真の監視を開始
  void startWatching() {
    if (_isWatching) return;
    _isWatching = true;

    // 初回同期
    syncNewPhotos();

    // 定期的にチェック（30秒間隔）
    _watchTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      syncNewPhotos();
    });
  }

  /// 写真の監視を停止
  void stopWatching() {
    _isWatching = false;
    _watchTimer?.cancel();
    _watchTimer = null;
  }

  /// 新しい写真を同期
  Future<void> syncNewPhotos() async {
    try {
      final permission = await PhotoManager.requestPermissionExtend();
      if (!permission.isAuth) return;

      final prefs = await SharedPreferences.getInstance();
      final lastSyncTime = prefs.getInt(_lastSyncKey) ?? 0;
      final lastSyncDate = DateTime.fromMillisecondsSinceEpoch(lastSyncTime);

      // 最近の写真を取得（最大50枚）
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        hasAll: true,
      );

      if (albums.isEmpty) return;

      // "Recent" または "All" アルバムを使用
      final recentAlbum = albums.first;
      final assets = await recentAlbum.getAssetListRange(start: 0, end: 50);

      int newPhotoCount = 0;

      for (final asset in assets) {
        // 最後の同期以降の写真のみ処理
        if (asset.createDateTime.isAfter(lastSyncDate)) {
          await _processPhoto(asset);
          newPhotoCount++;
        }
      }

      // 同期時刻を更新
      await prefs.setInt(_lastSyncKey, DateTime.now().millisecondsSinceEpoch);

      if (newPhotoCount > 0) {
        print('Synced $newPhotoCount new photos');
      }
    } catch (e) {
      print('Photo sync error: $e');
    }
  }

  /// 写真を処理してデータベースに保存
  Future<void> _processPhoto(AssetEntity asset) async {
    try {
      // 位置情報を取得
      final latLng = await asset.latlngAsync();
      double lat = latLng.latitude ?? 0;
      double lng = latLng.longitude ?? 0;
      bool isEstimatedLocation = false;

      // EXIFに位置情報がない場合、撮影日時から推測
      if (lat == 0 && lng == 0) {
        final estimatedLocation = await _estimateLocationFromTimestamp(asset.createDateTime);
        if (estimatedLocation != null) {
          lat = estimatedLocation['lat']!;
          lng = estimatedLocation['lng']!;
          isEstimatedLocation = true;
        } else {
          // 位置情報が推測できない場合はスキップ
          return;
        }
      }

      // 写真ファイルをアプリ内にコピー
      final file = await asset.file;
      if (file == null) return;

      final directory = await getApplicationDocumentsDirectory();
      final fileName = '${asset.id}_${asset.createDateTime.millisecondsSinceEpoch}.jpg';
      final savedPath = '${directory.path}/$fileName';

      // 既に保存済みかチェック
      if (await File(savedPath).exists()) return;

      await file.copy(savedPath);

      // 地点情報を取得
      String? placeName;
      String? address;
      try {
        final placeInfo = await GeocodingService.reverseGeocode(lat, lng);
        placeName = placeInfo?.shortName;
        address = placeInfo?.address;
      } catch (e) {
        // ジオコーディングエラーは無視
      }

      // データベースに保存
      final record = LocationRecord(
        latitude: lat,
        longitude: lng,
        timestamp: asset.createDateTime,
        imagePath: savedPath,
        placeName: placeName,
        address: address,
        note: isEstimatedLocation ? '📷 自動取得（位置推測）' : '📷 自動取得',
      );

      await DatabaseHelper.instance.create(record);
    } catch (e) {
      print('Process photo error: $e');
    }
  }

  /// 撮影日時からアプリの記録位置を推測
  /// 撮影時刻の前後5分以内の最も近い位置記録を使用
  Future<Map<String, double>?> _estimateLocationFromTimestamp(DateTime photoTime) async {
    try {
      // 写真撮影時刻の前後5分の記録を検索
      final records = await DatabaseHelper.instance.readLocationsByDate(photoTime);
      
      if (records.isEmpty) return null;

      // 撮影時刻に最も近い記録を探す
      LocationRecord? closestRecord;
      int minDiff = 5 * 60 * 1000; // 5分（ミリ秒）

      for (final record in records) {
        final diff = (record.timestamp.millisecondsSinceEpoch - photoTime.millisecondsSinceEpoch).abs();
        if (diff < minDiff) {
          minDiff = diff;
          closestRecord = record;
        }
      }

      if (closestRecord != null) {
        return {
          'lat': closestRecord.latitude,
          'lng': closestRecord.longitude,
        };
      }

      return null;
    } catch (e) {
      print('Location estimation error: $e');
      return null;
    }
  }

  /// 特定の日付範囲の写真を取得
  Future<List<AssetEntity>> getPhotosInRange(DateTime start, DateTime end) async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.isAuth) return [];

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      hasAll: true,
    );

    if (albums.isEmpty) return [];

    final recentAlbum = albums.first;
    final allAssets = await recentAlbum.getAssetListRange(start: 0, end: 1000);

    return allAssets.where((asset) {
      return asset.createDateTime.isAfter(start) &&
          asset.createDateTime.isBefore(end);
    }).toList();
  }
}
