import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// UWB（Ultra-Wideband）サービス
/// Android 12+ で利用可能なcm単位の超高精度測位
class UwbService extends ChangeNotifier {
  static final UwbService _instance = UwbService._internal();
  factory UwbService() => _instance;
  UwbService._internal();

  static const MethodChannel _channel = MethodChannel('uwb_service');
  
  bool _isSupported = false;
  bool _isAvailable = false;
  bool _isRanging = false;
  
  final Map<String, UwbRangingResult> _rangingResults = {};
  
  // ゲッター
  bool get isSupported => _isSupported;
  bool get isAvailable => _isAvailable;
  bool get isRanging => _isRanging;
  Map<String, UwbRangingResult> get rangingResults => Map.unmodifiable(_rangingResults);

  /// 初期化してUWBサポートを確認
  Future<void> initialize() async {
    try {
      final result = await _channel.invokeMethod('checkUwbSupport');
      _isSupported = result['isSupported'] ?? false;
      _isAvailable = result['isAvailable'] ?? false;
      
      if (_isSupported) {
        debugPrint('✅ UWB対応端末です！超高精度モードが利用可能です');
      } else {
        debugPrint('ℹ️ UWB非対応端末です（通常モードで動作）');
      }
      
      notifyListeners();
    } on PlatformException catch (e) {
      debugPrint('UWBサポート確認エラー: ${e.message}');
      _isSupported = false;
      _isAvailable = false;
    } catch (e) {
      debugPrint('UWB初期化エラー: $e');
      _isSupported = false;
      _isAvailable = false;
    }
  }

  /// UWB測距を開始
  Future<bool> startRanging(String targetId) async {
    if (!_isSupported || !_isAvailable) {
      debugPrint('UWBが利用できません');
      return false;
    }

    try {
      final result = await _channel.invokeMethod('startRanging', {
        'targetId': targetId,
      });
      
      _isRanging = result ?? false;
      
      if (_isRanging) {
        // 測距結果のストリームをリスン
        _channel.setMethodCallHandler(_handleUwbCallback);
        debugPrint('🎯 UWB測距開始: $targetId');
      }
      
      notifyListeners();
      return _isRanging;
    } on PlatformException catch (e) {
      debugPrint('UWB測距開始エラー: ${e.message}');
      return false;
    }
  }

  /// UWB測距を停止
  Future<void> stopRanging() async {
    if (!_isRanging) return;

    try {
      await _channel.invokeMethod('stopRanging');
      _isRanging = false;
      _rangingResults.clear();
      notifyListeners();
      debugPrint('UWB測距停止');
    } on PlatformException catch (e) {
      debugPrint('UWB測距停止エラー: ${e.message}');
    }
  }

  /// UWBコールバックハンドラ
  Future<dynamic> _handleUwbCallback(MethodCall call) async {
    switch (call.method) {
      case 'onRangingResult':
        final data = call.arguments as Map<dynamic, dynamic>;
        final result = UwbRangingResult(
          targetId: data['targetId'] as String,
          distanceCm: (data['distance'] as num).toDouble(),
          azimuthDegrees: (data['azimuth'] as num?)?.toDouble(),
          elevationDegrees: (data['elevation'] as num?)?.toDouble(),
          timestamp: DateTime.now(),
        );
        
        _rangingResults[result.targetId] = result;
        notifyListeners();
        
        debugPrint('📡 UWB測距: ${result.distanceCm}cm, 方位: ${result.azimuthDegrees}°');
        break;
        
      case 'onRangingError':
        final error = call.arguments as String;
        debugPrint('UWB測距エラー: $error');
        break;
    }
  }

  @override
  void dispose() {
    stopRanging();
    super.dispose();
  }
}

/// UWB測距結果
class UwbRangingResult {
  final String targetId;
  final double distanceCm; // cm単位の距離
  final double? azimuthDegrees; // 方位角（度）
  final double? elevationDegrees; // 仰角（度）
  final DateTime timestamp;

  UwbRangingResult({
    required this.targetId,
    required this.distanceCm,
    this.azimuthDegrees,
    this.elevationDegrees,
    required this.timestamp,
  });

  /// メートル単位の距離
  double get distanceMeters => distanceCm / 100.0;
}
