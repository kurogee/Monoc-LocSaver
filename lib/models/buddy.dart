/// 接続相手（バディ）の情報を保持するモデル
class Buddy {
  final String id;
  final String name;
  final String? deviceId;
  double? latitude;
  double? longitude;
  double? accuracy;
  DateTime? lastUpdate;
  double? distance; // メートル単位
  double? bearing; // 度数（北を0度として時計回り）
  bool isConnected;

  Buddy({
    required this.id,
    required this.name,
    this.deviceId,
    this.latitude,
    this.longitude,
    this.accuracy,
    this.lastUpdate,
    this.distance,
    this.bearing,
    this.isConnected = false,
  });

  /// 位置情報を更新
  void updateLocation({
    required double lat,
    required double lng,
    double? acc,
  }) {
    latitude = lat;
    longitude = lng;
    accuracy = acc;
    lastUpdate = DateTime.now();
  }

  /// JSONからBuddyを作成
  factory Buddy.fromJson(Map<String, dynamic> json) {
    return Buddy(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Unknown',
      deviceId: json['deviceId'],
      latitude: json['latitude']?.toDouble(),
      longitude: json['longitude']?.toDouble(),
      accuracy: json['accuracy']?.toDouble(),
      lastUpdate: json['lastUpdate'] != null 
          ? DateTime.tryParse(json['lastUpdate']) 
          : null,
      isConnected: json['isConnected'] ?? false,
    );
  }

  /// BuddyをJSONに変換
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'deviceId': deviceId,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'lastUpdate': lastUpdate?.toIso8601String(),
      'isConnected': isConnected,
    };
  }

  /// 位置情報の送信用データ
  Map<String, dynamic> toLocationPayload() {
    return {
      'type': 'location',
      'id': id,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  @override
  String toString() {
    return 'Buddy(id: $id, name: $name, connected: $isConnected, lat: $latitude, lng: $longitude)';
  }
}
