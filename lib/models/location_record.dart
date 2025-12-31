class LocationRecord {
  final int? id;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final String? note;
  final String? imagePath;
  final double? speed; // 速度 (m/s)
  final double? accuracy; // 精度 (m)
  final String? transportMode; // 移動手段: walking, cycling, driving, train, stationary
  final bool? isStayPoint; // 滞在地点かどうか
  final int? stayDurationMinutes; // 滞在時間（分）
  final String? placeName; // 場所の名前（ユーザー入力または自動）
  final String? placeType; // 場所の種類（restaurant, station等）
  final String? address; // 住所
  final String? roadType; // 道路種別（highway, primary等）
  final bool? isHighway; // 高速道路・有料道路かどうか
  final bool? isRailway; // 鉄道かどうか

  LocationRecord({
    this.id,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.note,
    this.imagePath,
    this.speed,
    this.accuracy,
    this.transportMode,
    this.isStayPoint,
    this.stayDurationMinutes,
    this.placeName,
    this.placeType,
    this.address,
    this.roadType,
    this.isHighway,
    this.isRailway,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.toIso8601String(),
      'note': note,
      'image_path': imagePath,
      'speed': speed,
      'accuracy': accuracy,
      'transport_mode': transportMode,
      'is_stay_point': isStayPoint == true ? 1 : 0,
      'stay_duration_minutes': stayDurationMinutes,
      'place_name': placeName,
      'place_type': placeType,
      'address': address,
      'road_type': roadType,
      'is_highway': isHighway == true ? 1 : 0,
      'is_railway': isRailway == true ? 1 : 0,
    };
  }

  factory LocationRecord.fromMap(Map<String, dynamic> map) {
    return LocationRecord(
      id: map['id'],
      latitude: map['latitude'],
      longitude: map['longitude'],
      timestamp: DateTime.parse(map['timestamp']),
      note: map['note'],
      imagePath: map['image_path'],
      speed: map['speed'],
      accuracy: map['accuracy'],
      transportMode: map['transport_mode'],
      isStayPoint: map['is_stay_point'] == 1,
      stayDurationMinutes: map['stay_duration_minutes'],
      placeName: map['place_name'],
      placeType: map['place_type'],
      address: map['address'],
      roadType: map['road_type'],
      isHighway: map['is_highway'] == 1,
      isRailway: map['is_railway'] == 1,
    );
  }

  LocationRecord copyWith({
    int? id,
    double? latitude,
    double? longitude,
    DateTime? timestamp,
    String? note,
    String? imagePath,
    double? speed,
    double? accuracy,
    String? transportMode,
    bool? isStayPoint,
    int? stayDurationMinutes,
    String? placeName,
    String? placeType,
    String? address,
    String? roadType,
    bool? isHighway,
    bool? isRailway,
  }) {
    return LocationRecord(
      id: id ?? this.id,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      timestamp: timestamp ?? this.timestamp,
      note: note ?? this.note,
      imagePath: imagePath ?? this.imagePath,
      speed: speed ?? this.speed,
      accuracy: accuracy ?? this.accuracy,
      transportMode: transportMode ?? this.transportMode,
      isStayPoint: isStayPoint ?? this.isStayPoint,
      stayDurationMinutes: stayDurationMinutes ?? this.stayDurationMinutes,
      placeName: placeName ?? this.placeName,
      placeType: placeType ?? this.placeType,
      address: address ?? this.address,
      roadType: roadType ?? this.roadType,
      isHighway: isHighway ?? this.isHighway,
      isRailway: isRailway ?? this.isRailway,
    );
  }
}
