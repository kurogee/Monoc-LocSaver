import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:monoc_locsaver/models/buddy.dart';

/// Nearby Connections を使用した P2P 接続サービス
/// Bluetooth + WiFi Direct を活用して近くのデバイスと接続
class NearbyService extends ChangeNotifier {
  static final NearbyService _instance = NearbyService._internal();
  factory NearbyService() => _instance;
  NearbyService._internal();

  // サービスID（同じアプリ同士の識別用）
  static const String _serviceId = 'com.monoclocsaver.finder';
  
  // 接続戦略（P2P_CLUSTER: 複数デバイス間の接続に最適）
  static const Strategy _strategy = Strategy.P2P_CLUSTER;

  // 自分の情報
  String _myId = '';
  String _myName = '名前未設定';
  
  // 接続状態
  bool _isAdvertising = false;
  bool _isDiscovering = false;
  bool _hasPermissions = false;
  
  // 検出したデバイス
  final Map<String, Buddy> _discoveredBuddies = {};
  
  // 接続済みのバディ
  final Map<String, Buddy> _connectedBuddies = {};
  
  // 現在位置
  Position? _currentPosition;
  
  // 位置情報送信タイマー
  Timer? _locationTimer;
  
  // 位置情報フィルタリング用
  final List<Position> _positionHistory = [];
  static const int _maxHistorySize = 5;
  
  // ゲッター
  String get myId => _myId;
  String get myName => _myName;
  bool get isAdvertising => _isAdvertising;
  bool get isDiscovering => _isDiscovering;
  bool get hasPermissions => _hasPermissions;
  List<Buddy> get discoveredBuddies => _discoveredBuddies.values.toList();
  List<Buddy> get connectedBuddies => _connectedBuddies.values.toList();
  Position? get currentPosition => _currentPosition;

  /// 初期化
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _myId = prefs.getString('buddy_id') ?? _generateId();
    _myName = prefs.getString('buddy_name') ?? 'ユーザー${_myId.substring(0, 4)}';
    
    await prefs.setString('buddy_id', _myId);
    await prefs.setString('buddy_name', _myName);
    
    notifyListeners();
  }

  /// ランダムIDを生成
  String _generateId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random();
    return String.fromCharCodes(
      Iterable.generate(8, (_) => chars.codeUnitAt(random.nextInt(chars.length))),
    );
  }

  /// 名前を設定
  Future<void> setMyName(String name) async {
    _myName = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('buddy_name', name);
    notifyListeners();
  }

  /// 必要なパーミッションをリクエスト
  Future<bool> requestPermissions() async {
    try {
      // 位置情報パーミッション（必須）
      var locationStatus = await Permission.location.status;
      if (!locationStatus.isGranted) {
        locationStatus = await Permission.location.request();
        if (!locationStatus.isGranted) {
          debugPrint('位置情報パーミッションが拒否されました');
          _hasPermissions = false;
          notifyListeners();
          return false;
        }
      }
      
      // 位置情報サービスが有効かチェック
      try {
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          debugPrint('位置情報サービスが無効です');
          // サービスが無効でも権限はあるのでtrueを返す（ユーザーに有効化を促す必要あり）
        }
      } catch (e) {
        debugPrint('位置情報サービスチェックエラー: $e');
      }
      
      // Bluetoothパーミッション（Android 12以上で必要）
      try {
        // Android 12以上の場合、新しいBluetooth権限が必要
        final bluetoothConnect = await Permission.bluetoothConnect.status;
        final bluetoothScan = await Permission.bluetoothScan.status;
        final bluetoothAdvertise = await Permission.bluetoothAdvertise.status;
        
        // 権限が未取得の場合のみリクエスト
        if (!bluetoothConnect.isGranted || !bluetoothScan.isGranted || !bluetoothAdvertise.isGranted) {
          final statuses = await [
            Permission.bluetoothConnect,
            Permission.bluetoothScan,
            Permission.bluetoothAdvertise,
          ].request();
          
          // いずれかが拒否された場合はログ出力（動作は継続）
          for (var entry in statuses.entries) {
            if (!entry.value.isGranted) {
              debugPrint('${entry.key} が許可されませんでした: ${entry.value}');
            }
          }
        }
      } catch (e) {
        // Android 11以下では無視（Manifestの権限で動作）
        debugPrint('Bluetooth権限（Android 12+）のリクエストをスキップ: $e');
      }
      
      // Nearby Wifiデバイス（Android 13以上）
      try {
        final nearbyWifi = await Permission.nearbyWifiDevices.status;
        if (!nearbyWifi.isGranted) {
          await Permission.nearbyWifiDevices.request();
        }
      } catch (e) {
        // 対応していない場合は無視
        debugPrint('Nearby WiFi権限のリクエストをスキップ: $e');
      }
      
      _hasPermissions = locationStatus.isGranted;
      debugPrint('パーミッション取得完了 - 位置情報: ${locationStatus.isGranted}');
      
      notifyListeners();
      return _hasPermissions;
    } catch (e) {
      debugPrint('パーミッション取得エラー: $e');
      // エラーが発生した場合でも、基本的な位置情報権限があればOKとする
      try {
        final locationStatus = await Permission.location.status;
        _hasPermissions = locationStatus.isGranted;
      } catch (e2) {
        _hasPermissions = false;
      }
      notifyListeners();
      return _hasPermissions;
    }
  }

  /// アドバタイズを開始（自分を見つけてもらう）
  Future<bool> startAdvertising() async {
    if (_isAdvertising) return true;
    
    try {
      bool result = await Nearby().startAdvertising(
        _myName,
        _strategy,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
        serviceId: _serviceId,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('アドバタイズ開始がタイムアウトしました');
          return false;
        },
      );
      
      _isAdvertising = result;
      notifyListeners();
      return result;
    } catch (e) {
      debugPrint('アドバタイズ開始エラー: $e');
      _isAdvertising = false;
      notifyListeners();
      return false;
    }
  }

  /// アドバタイズを停止
  Future<void> stopAdvertising() async {
    try {
      await Nearby().stopAdvertising();
      _isAdvertising = false;
      notifyListeners();
    } catch (e) {
      debugPrint('アドバタイズ停止エラー: $e');
    }
  }

  /// ディスカバリーを開始（他のデバイスを探す）
  Future<bool> startDiscovery() async {
    if (_isDiscovering) return true;
    
    try {
      bool result = await Nearby().startDiscovery(
        _myName,
        _strategy,
        onEndpointFound: _onEndpointFound,
        onEndpointLost: _onEndpointLost,
        serviceId: _serviceId,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('ディスカバリー開始がタイムアウトしました');
          return false;
        },
      );
      
      _isDiscovering = result;
      notifyListeners();
      return result;
    } catch (e) {
      debugPrint('ディスカバリー開始エラー: $e');
      _isDiscovering = false;
      notifyListeners();
      return false;
    }
  }

  /// ディスカバリーを停止
  Future<void> stopDiscovery() async {
    try {
      await Nearby().stopDiscovery();
      _isDiscovering = false;
      notifyListeners();
    } catch (e) {
      debugPrint('ディスカバリー停止エラー: $e');
    }
  }

  /// エンドポイント（デバイス）が見つかった時
  void _onEndpointFound(String endpointId, String endpointName, String serviceId) {
    debugPrint('デバイス発見: $endpointName ($endpointId)');
    
    final buddy = Buddy(
      id: endpointId,
      name: endpointName,
      deviceId: endpointId,
      isConnected: false,
    );
    
    _discoveredBuddies[endpointId] = buddy;
    notifyListeners();
  }

  /// エンドポイントを見失った時
  void _onEndpointLost(String? endpointId) {
    if (endpointId != null) {
      debugPrint('デバイスロスト: $endpointId');
      _discoveredBuddies.remove(endpointId);
      notifyListeners();
    }
  }

  /// 接続をリクエスト
  Future<bool> requestConnection(String endpointId) async {
    try {
      await Nearby().requestConnection(
        _myName,
        endpointId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
      return true;
    } catch (e) {
      debugPrint('接続リクエストエラー: $e');
      return false;
    }
  }

  /// 接続が開始された時（承認待ち）
  void _onConnectionInitiated(String endpointId, ConnectionInfo info) {
    debugPrint('接続開始: ${info.endpointName} ($endpointId)');
    
    // 自動的に接続を承認
    try {
      Nearby().acceptConnection(
        endpointId,
        onPayLoadRecieved: _onPayloadReceived,
        onPayloadTransferUpdate: _onPayloadTransferUpdate,
      );
    } catch (e) {
      debugPrint('接続承認エラー: $e');
    }
  }

  /// 接続結果
  void _onConnectionResult(String endpointId, Status status) {
    debugPrint('接続結果: $endpointId - ${status.name}');
    
    if (status == Status.CONNECTED) {
      // 接続成功
      final buddy = _discoveredBuddies[endpointId];
      if (buddy != null) {
        buddy.isConnected = true;
        _connectedBuddies[endpointId] = buddy;
        _discoveredBuddies.remove(endpointId);
      } else {
        // 新規バディとして追加
        _connectedBuddies[endpointId] = Buddy(
          id: endpointId,
          name: 'バディ',
          deviceId: endpointId,
          isConnected: true,
        );
      }
      
      // 位置情報の定期送信を開始
      _startLocationSharing();
      
      notifyListeners();
    } else {
      // 接続失敗
      debugPrint('接続失敗: ${status.name}');
    }
  }

  /// 切断された時
  void _onDisconnected(String endpointId) {
    debugPrint('切断: $endpointId');
    _connectedBuddies.remove(endpointId);
    notifyListeners();
  }

  /// ペイロード（データ）を受信した時
  void _onPayloadReceived(String endpointId, Payload payload) {
    if (payload.type == PayloadType.BYTES && payload.bytes != null) {
      try {
        final data = utf8.decode(payload.bytes!);
        final json = jsonDecode(data) as Map<String, dynamic>;
        
        if (json['type'] == 'location') {
          _handleLocationUpdate(endpointId, json);
        }
      } catch (e) {
        debugPrint('ペイロード解析エラー: $e');
      }
    }
  }

  /// ペイロード転送状況
  void _onPayloadTransferUpdate(String endpointId, PayloadTransferUpdate update) {
    // 必要に応じて進捗表示など
  }

  /// 位置情報の更新を処理
  void _handleLocationUpdate(String endpointId, Map<String, dynamic> data) {
    final buddy = _connectedBuddies[endpointId];
    if (buddy != null) {
      final newLat = data['latitude']?.toDouble() ?? 0;
      final newLng = data['longitude']?.toDouble() ?? 0;
      final accuracy = data['accuracy']?.toDouble();
      
      // 精度によるフィルタリング（段階的）
      if (accuracy != null) {
        // 非常に精度が低い場合は無視（100m以上の誤差）
        if (accuracy > 100) {
          debugPrint('精度が非常に低いため更新をスキップ: ${accuracy}m');
          return;
        }
        // 精度がやや低い場合（50-100m）は前回の位置と加重平均
        if (accuracy > 50 && buddy.latitude != null && buddy.longitude != null) {
          // 前回の位置と新しい位置を加重平均（精度が低いほど影響小）
          final weight = 1.0 / accuracy; // 精度が低いほどウェイト小
          final prevWeight = 1.0 / (buddy.accuracy ?? 50);
          final totalWeight = weight + prevWeight;
          
          final avgLat = (newLat * weight + buddy.latitude! * prevWeight) / totalWeight;
          final avgLng = (newLng * weight + buddy.longitude! * prevWeight) / totalWeight;
          
          buddy.updateLocation(
            lat: avgLat,
            lng: avgLng,
            acc: (accuracy + (buddy.accuracy ?? 50)) / 2,
          );
          debugPrint('精度がやや低いため加重平均を適用: ${accuracy}m');
        } else {
          // 精度が高い場合はそのまま使用
          buddy.updateLocation(
            lat: newLat,
            lng: newLng,
            acc: accuracy,
          );
        }
      } else {
        buddy.updateLocation(
          lat: newLat,
          lng: newLng,
          acc: null,
        );
      }
      
      // 前回の位置から大きく離れすぎている場合は無視（3秒で200m以上）
      // （障害物によるGPSのマルチパスエラーを防ぐ）
      if (buddy.lastUpdateTime != null) {
        final timeDiff = DateTime.now().difference(buddy.lastUpdateTime!).inSeconds;
        if (timeDiff > 0 && buddy.distance != null) {
          final oldLat = buddy.latitude;
          final oldLng = buddy.longitude;
          
          if (oldLat != null && oldLng != null) {
            final jumpDistance = _calculateDistance(oldLat, oldLng, newLat, newLng);
            final maxReasonableSpeed = 200.0 / 3.0; // 3秒で200m = 67m/s 約240km/h
            
            if (jumpDistance / timeDiff > maxReasonableSpeed) {
              debugPrint('位置の変化が大きすぎるため更新をスキップ: ${jumpDistance.toStringAsFixed(1)}m / ${timeDiff}s');
              return;
            }
          }
        }
      }
      buddy.lastUpdateTime = DateTime.now();
      
      // 名前の更新
      if (data['name'] != null) {
        buddy.name = data['name'];
      }
      
      // 速度と方向の更新
      if (data['speed'] != null) {
        buddy.speed = data['speed'].toDouble();
      }
      if (data['heading'] != null) {
        buddy.movementHeading = data['heading'].toDouble();
      }
      
      // 距離と方角を計算
      if (_currentPosition != null && buddy.latitude != null && buddy.longitude != null) {
        final newDistance = _calculateDistance(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          buddy.latitude!,
          buddy.longitude!,
        );
        
        // 移動速度を考慮した予測距離（次の更新までの推定位置）
        if (buddy.speed != null && buddy.movementHeading != null && buddy.speed! > 0.5) {
          // 3秒後の予測位置を計算
          const predictionTime = 3.0; // 秒
          final predictedDistance = buddy.speed! * predictionTime;
          final radHeading = buddy.movementHeading! * pi / 180;
          
          // 移動方向の変化率を計算（前回との差分）
          double angularVelocity = 0.0;
          if (buddy.movementHeading != null && buddy.lastUpdateTime != null) {
            final timeDiff = DateTime.now().difference(buddy.lastUpdateTime!).inMilliseconds / 1000.0;
            if (timeDiff > 0 && timeDiff < 5) {
              // 前回の方向が記録されていれば角速度を計算
              // （簡略化のため、ここではスキップ）
            }
          }
          
          // 角速度が大きい（方向転換中）は予測を下げる
          double predictionWeight = min(buddy.speed! / 5.0, 0.5); // 最大50%まで予測を使用
          if (angularVelocity.abs() > 30) { // 30度/秒以上の回転
            predictionWeight *= 0.3; // 予測ウェイトを下げる
          }
          
          // 予測位置への移動量
          final deltaLat = predictedDistance * cos(radHeading) / 111320; // 緯度1度≈111.32km
          final deltaLng = predictedDistance * sin(radHeading) / (111320 * cos(buddy.latitude! * pi / 180));
          
          final predictedLat = buddy.latitude! + deltaLat;
          final predictedLng = buddy.longitude! + deltaLng;
          
          // 予測位置までの距離と方角
          final predictedDist = _calculateDistance(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
            predictedLat,
            predictedLng,
          );
          
          // 現在と予測の加重平均
          buddy.distance = newDistance * (1 - predictionWeight) + predictedDist * predictionWeight;
          
          buddy.bearing = _calculateBearing(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
            predictedLat * predictionWeight + buddy.latitude! * (1 - predictionWeight),
            predictedLng * predictionWeight + buddy.longitude! * (1 - predictionWeight),
          );
        } else {
          // 静止または低速の場合は通常の計算
          buddy.distance = newDistance;
          buddy.bearing = _calculateBearing(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
            buddy.latitude!,
            buddy.longitude!,
          );
        }
      }
      
      notifyListeners();
    }
  }

  /// 位置情報の共有を開始
  void _startLocationSharing() {
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _sendLocationToAll();
    });
    // 即座に一度送信
    _sendLocationToAll();
  }

  /// 位置情報の共有を停止
  void _stopLocationSharing() {
    _locationTimer?.cancel();
    _locationTimer = null;
  }

  /// 全接続先に位置情報を送信
  Future<void> _sendLocationToAll() async {
    try {
      // 位置情報サービスが有効かチェック
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('位置情報サービスが無効です - 送信をスキップ');
        return;
      }
      
      // 権限チェック
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        debugPrint('位置情報権限がありません - 送信をスキップ');
        return;
      }
      
      // 高精度で位置情報を取得（bestAccuracyで最高精度）
      final newPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation, // ナビゲーション用最高精度
        timeLimit: const Duration(seconds: 5),
      ).timeout(
        const Duration(seconds: 7),
        onTimeout: () {
          throw TimeoutException('位置情報取得がタイムアウトしました');
        },
      );
      
      // 位置履歴に追加して平滑化（ノイズ削減）
      _positionHistory.add(newPosition);
      if (_positionHistory.length > _maxHistorySize) {
        _positionHistory.removeAt(0);
      }
      
      // 精度を考慮した加重平均位置を計算（精度が高いほどウェイト大）
      double totalWeight = 0;
      double weightedLat = 0;
      double weightedLng = 0;
      double bestAccuracy = double.infinity;
      
      for (var pos in _positionHistory) {
        // 精度をウェイトとして使用（精度が高い＝値が小さいほどウェイト大）
        final weight = 1.0 / (pos.accuracy + 1.0); // +1でゼロ除算回避
        weightedLat += pos.latitude * weight;
        weightedLng += pos.longitude * weight;
        totalWeight += weight;
        if (pos.accuracy < bestAccuracy) {
          bestAccuracy = pos.accuracy;
        }
      }
      
      final avgLat = weightedLat / totalWeight;
      final avgLng = weightedLng / totalWeight;
      final avgAccuracy = bestAccuracy; // 最高精度を使用
      
      _currentPosition = Position(
        latitude: avgLat,
        longitude: avgLng,
        timestamp: newPosition.timestamp,
        accuracy: avgAccuracy,
        altitude: newPosition.altitude,
        altitudeAccuracy: newPosition.altitudeAccuracy,
        heading: newPosition.heading,
        headingAccuracy: newPosition.headingAccuracy,
        speed: newPosition.speed,
        speedAccuracy: newPosition.speedAccuracy,
      );
      
      if (_currentPosition == null) return;
      
      final payload = {
        'type': 'location',
        'id': _myId,
        'name': _myName,
        'latitude': _currentPosition!.latitude,
        'longitude': _currentPosition!.longitude,
        'accuracy': _currentPosition!.accuracy,
        'timestamp': DateTime.now().toIso8601String(),
        'heading': _currentPosition!.heading, // 移動方向
        'speed': _currentPosition!.speed, // 移動速度
      };
      
      final bytes = utf8.encode(jsonEncode(payload));
      
      for (final buddy in _connectedBuddies.values) {
        if (buddy.id.isEmpty) {
          debugPrint('無効なbuddy IDをスキップ');
          continue;
        }
        try {
          await Nearby().sendBytesPayload(buddy.id, Uint8List.fromList(bytes));
        } catch (e) {
          debugPrint('位置送信エラー (${buddy.name}): $e');
        }
      }
      
      // 接続先の距離・方角も更新
      for (final buddy in _connectedBuddies.values) {
        if (buddy.latitude != null && buddy.longitude != null) {
          buddy.distance = _calculateDistance(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
            buddy.latitude!,
            buddy.longitude!,
          );
          buddy.bearing = _calculateBearing(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
            buddy.latitude!,
            buddy.longitude!,
          );
        }
      }
      
      notifyListeners();
    } on TimeoutException catch (e) {
      debugPrint('位置情報取得タイムアウト: $e');
      // 前回の位置情報を使い続ける
    } on LocationServiceDisabledException catch (e) {
      debugPrint('位置情報サービスが無効: $e');
    } on PermissionDeniedException catch (e) {
      debugPrint('位置情報権限が拒否されました: $e');
      _hasPermissions = false;
      notifyListeners();
    } catch (e) {
      debugPrint('位置情報取得エラー: $e');
    }
  }

  /// 2点間の距離を計算（メートル）
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // メートル
    
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) *
        sin(dLon / 2) * sin(dLon / 2);
    
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    
    return earthRadius * c;
  }

  /// 方位角を計算（度数、北を0度として時計回り）
  double _calculateBearing(double lat1, double lon1, double lat2, double lon2) {
    final dLon = _toRadians(lon2 - lon1);
    
    final y = sin(dLon) * cos(_toRadians(lat2));
    final x = cos(_toRadians(lat1)) * sin(_toRadians(lat2)) -
        sin(_toRadians(lat1)) * cos(_toRadians(lat2)) * cos(dLon);
    
    final bearing = atan2(y, x);
    return (_toDegrees(bearing) + 360) % 360;
  }

  double _toRadians(double degrees) => degrees * pi / 180;
  double _toDegrees(double radians) => radians * 180 / pi;

  /// RSSIから距離を推定（フォールバック用）
  /// Path Loss Model: d = 10^((TxPower - RSSI) / (10 * n))
  /// n = 環境係数（屋外:2-3, 屋内:3-4）
  double _estimateDistanceFromRSSI(int rssi, {double txPower = -59, double environmentFactor = 3.0}) {
    if (rssi == 0) return -1.0; // 無効なRSSI
    
    // 距離計算
    final ratio = (txPower - rssi) / (10 * environmentFactor);
    final distance = pow(10, ratio).toDouble();
    
    // 非現実的な値をフィルタリング（1m未満または100m以上）
    if (distance < 1.0) return 1.0;
    if (distance > 100.0) return 100.0;
    
    return distance;
  }
  
  /// 距離をマルチパスフェーディングを考慮して補正
  /// 複数のRSSI測定値の中央値を使用（外れ値に強い）
  double _filterRSSIDistance(List<double> distances) {
    if (distances.isEmpty) return -1.0;
    if (distances.length == 1) return distances[0];
    
    final sorted = List<double>.from(distances)..sort();
    return sorted[sorted.length ~/ 2]; // 中央値
  }

  /// 接続を切断
  Future<void> disconnect(String endpointId) async {
    try {
      await Nearby().disconnectFromEndpoint(endpointId);
      _connectedBuddies.remove(endpointId);
      notifyListeners();
    } catch (e) {
      debugPrint('切断エラー: $e');
    }
  }

  /// すべての接続を切断
  Future<void> disconnectAll() async {
    try {
      await Nearby().stopAllEndpoints();
      _connectedBuddies.clear();
      notifyListeners();
    } catch (e) {
      debugPrint('全切断エラー: $e');
    }
  }

  /// サービスを停止
  Future<void> stopAll() async {
    _stopLocationSharing();
    await stopAdvertising();
    await stopDiscovery();
    await disconnectAll();
    _discoveredBuddies.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _stopLocationSharing();
    super.dispose();
  }
}
