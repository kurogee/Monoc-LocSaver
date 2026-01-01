import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// 高精度センサーフュージョンサービス
/// IMUセンサー（加速度、ジャイロ、磁気）を統合して高精度な方位と移動を推定
class SensorFusionService extends ChangeNotifier {
  static final SensorFusionService _instance = SensorFusionService._internal();
  factory SensorFusionService() => _instance;
  SensorFusionService._internal();

  // センサーストリーム
  StreamSubscription<AccelerometerEvent>? _accelSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroSubscription;
  StreamSubscription<MagnetometerEvent>? _magSubscription;

  // センサーデータ
  double _heading = 0.0; // 方位角（度）
  double _pitch = 0.0;   // ピッチ角
  double _roll = 0.0;    // ロール角
  
  // 加速度データ（PDR用）
  double _accX = 0.0;
  double _accY = 0.0;
  double _accZ = 0.0;
  
  // ジャイロデータ
  double _gyroX = 0.0;
  double _gyroY = 0.0;
  double _gyroZ = 0.0;
  
  // 磁気データ
  double _magX = 0.0;
  double _magY = 0.0;
  double _magZ = 0.0;

  // 拡張カルマンフィルタのパラメータ
  final List<double> _quaternion = [1.0, 0.0, 0.0, 0.0]; // [w, x, y, z]
  double _beta = 0.1; // フィルタゲイン（動的調整）
  
  // PDR（歩行者推測航法）パラメータ
  int _stepCount = 0;
  double _lastMagnitude = 0.0;
  double _stepThreshold = 1.5; // 歩行検出の閾値（m/s²）
  double _averageStepLength = 0.7; // 平均歩幅（メートル、動的調整）
  DateTime _lastStepTime = DateTime.now();
  List<double> _stepLengthHistory = []; // 歩幅履歴（キャリブレーション用）
  
  // センサー信頼度スコア（0-100）
  double _sensorReliabilityScore = 50.0;
  double _magneticFieldStrength = 0.0;
  double _accelerationVariance = 0.0;
  final List<double> _magStrengthHistory = [];
  final List<double> _accelVarianceHistory = [];
  
  // 移動量の推定
  double _estimatedX = 0.0; // X方向の累積移動（メートル）
  double _estimatedY = 0.0; // Y方向の累積移動（メートル）
  
  // 拡張カルマンフィルタ用の状態
  List<double> _stateEstimate = [0.0, 0.0, 0.0, 0.0]; // [heading, velocity, x, y]
  List<List<double>> _covarianceMatrix = [
    [1.0, 0.0, 0.0, 0.0],
    [0.0, 1.0, 0.0, 0.0],
    [0.0, 0.0, 1.0, 0.0],
    [0.0, 0.0, 0.0, 1.0],
  ];

  // ゲッター
  double get heading => _heading;
  double get pitch => _pitch;
  double get roll => _roll;
  int get stepCount => _stepCount;
  double get estimatedX => _estimatedX;
  double get estimatedY => _estimatedY;
  double get sensorReliabilityScore => _sensorReliabilityScore;
  double get averageStepLength => _averageStepLength;
  
  /// 初期化
  void initialize() {
    _setupSensors();
  }

  /// センサーのセットアップ
  void _setupSensors() {
    // 加速度センサー（100Hz）
    _accelSubscription = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 10),
    ).listen(_onAccelerometerEvent);

    // ジャイロセンサー（100Hz）
    _gyroSubscription = gyroscopeEventStream(
      samplingPeriod: const Duration(milliseconds: 10),
    ).listen(_onGyroscopeEvent);

    // 磁気センサー（50Hz）
    _magSubscription = magnetometerEventStream(
      samplingPeriod: const Duration(milliseconds: 20),
    ).listen(_onMagnetometerEvent);
  }

  /// 加速度センサーイベント
  void _onAccelerometerEvent(AccelerometerEvent event) {
    _accX = event.x;
    _accY = event.y;
    _accZ = event.z;
    
    // 加速度の分散を計算（ノイズ評価）
    final magnitude = sqrt(_accX * _accX + _accY * _accY + _accZ * _accZ);
    final deviation = (magnitude - 9.81).abs(); // 重力加速度からの偏差
    _accelVarianceHistory.add(deviation);
    if (_accelVarianceHistory.length > 20) {
      _accelVarianceHistory.removeAt(0);
    }
    
    // PDR: 歩行検出
    _detectStep();
    
    // センサーフュージョン更新
    _updateSensorFusion();
  }

  /// ジャイロセンサーイベント
  void _onGyroscopeEvent(GyroscopeEvent event) {
    _gyroX = event.x;
    _gyroY = event.y;
    _gyroZ = event.z;
  }

  /// 磁気センサーイベント
  void _onMagnetometerEvent(MagnetometerEvent event) {
    _magX = event.x;
    _magY = event.y;
    _magZ = event.z;
    
    // 磁界強度を計算（信頼度評価用）
    _magneticFieldStrength = sqrt(_magX * _magX + _magY * _magY + _magZ * _magZ);
    _magStrengthHistory.add(_magneticFieldStrength);
    if (_magStrengthHistory.length > 20) {
      _magStrengthHistory.removeAt(0);
    }
    
    // センサー信頼度を更新
    _updateSensorReliability();
  }

  /// 歩行検出（PDR）
  void _detectStep() {
    // 加速度の大きさを計算
    final magnitude = sqrt(_accX * _accX + _accY * _accY + _accZ * _accZ);
    
    // 前回との差分が閾値を超えたら歩行検出
    final diff = (magnitude - _lastMagnitude).abs();
    final now = DateTime.now();
    final timeSinceLastStep = now.difference(_lastStepTime).inMilliseconds;
    
    // 歩行パターン検出（0.3秒〜1.5秒間隔で差分が大きい場合）
    if (diff > _stepThreshold && timeSinceLastStep > 300 && timeSinceLastStep < 1500) {
      _stepCount++;
      _lastStepTime = now;
      
      // 移動量を推定（現在の向きに基づいて）
      final radHeading = _heading * pi / 180;
      _estimatedX += _averageStepLength * sin(radHeading);
      _estimatedY += _averageStepLength * cos(radHeading);
      
      debugPrint('歩行検出: $_stepCount歩 - 移動: (${_estimatedX.toStringAsFixed(2)}, ${_estimatedY.toStringAsFixed(2)})');
      notifyListeners();
    }
    
    _lastMagnitude = magnitude;
  }

  /// センサー信頼度を評価（0-100のスコア）
  void _updateSensorReliability() {
    double score = 100.0;
    
    // 1. 磁気センサーの信頼度（地磁気: 25-65 μT）
    if (_magStrengthHistory.length >= 10) {
      final avgMag = _magStrengthHistory.reduce((a, b) => a + b) / _magStrengthHistory.length;
      
      // 正常範囲: 25-65 μT
      if (avgMag < 20 || avgMag > 80) {
        score -= 30; // 磁気異常（鉄骨建物など）
      } else if (avgMag < 25 || avgMag > 65) {
        score -= 15; // やや異常
      }
      
      // 磁界の分散（安定性）
      final variance = _magStrengthHistory
        .map((v) => pow(v - avgMag, 2))
        .reduce((a, b) => a + b) / _magStrengthHistory.length;
      
      if (variance > 100) {
        score -= 20; // 磁界が不安定
      } else if (variance > 50) {
        score -= 10;
      }
    }
    
    // 2. 加速度センサーの信頼度（ノイズレベル）
    if (_accelVarianceHistory.length >= 10) {
      final avgDeviation = _accelVarianceHistory.reduce((a, b) => a + b) / _accelVarianceHistory.length;
      
      // 静止中は9.81 m/s²に近いはず
      if (avgDeviation > 2.0) {
        score -= 20; // 激しい振動
      } else if (avgDeviation > 1.0) {
        score -= 10; // やや振動
      }
    }
    
    // 3. ジャイロの角速度（急激な回転）
    final gyroMagnitude = sqrt(_gyroX * _gyroX + _gyroY * _gyroY + _gyroZ * _gyroZ);
    if (gyroMagnitude > 3.0) {
      score -= 15; // 急激な回転中
    } else if (gyroMagnitude > 1.5) {
      score -= 5;
    }
    
    // スコアを0-100に制限
    _sensorReliabilityScore = score.clamp(0, 100);
    
    // β値を動的調整（信頼度が低いほどジャイロ寄り）
    if (_sensorReliabilityScore > 80) {
      _beta = 0.15; // 高信頼: 測定値を信じる
    } else if (_sensorReliabilityScore > 60) {
      _beta = 0.10; // 中信頼: バランス
    } else if (_sensorReliabilityScore > 40) {
      _beta = 0.05; // 低信頼: ジャイロ寄り
    } else {
      _beta = 0.02; // 非常に低信頼: ほぼジャイロのみ
    }
  }

  /// 歩幅をキャリブレーション（GPS/RSSI距離が取得できた時）
  void calibrateStepLength(double actualDistance, int stepsSinceLastCalibration) {
    if (stepsSinceLastCalibration < 3) return; // 最低3歩必要
    
    final measuredStepLength = actualDistance / stepsSinceLastCalibration;
    
    // 非現実的な値は無視（0.3m〜1.2m）
    if (measuredStepLength < 0.3 || measuredStepLength > 1.2) {
      debugPrint('非現実的な歩幅: ${measuredStepLength.toStringAsFixed(2)}m - 無視');
      return;
    }
    
    _stepLengthHistory.add(measuredStepLength);
    if (_stepLengthHistory.length > 10) {
      _stepLengthHistory.removeAt(0);
    }
    
    // 移動平均で歩幅を更新
    _averageStepLength = _stepLengthHistory.reduce((a, b) => a + b) / _stepLengthHistory.length;
    
    debugPrint('歩幅キャリブレーション: ${_averageStepLength.toStringAsFixed(2)}m (${_stepLengthHistory.length}サンプル)');
    notifyListeners();
  }

  /// センサーフュージョン更新（Madgwickアルゴリズム）
  void _updateSensorFusion() {
    const dt = 0.01; // サンプリング周期（10ms = 0.01s）
    
    // クォータニオンの正規化
    final qNorm = sqrt(_quaternion[0] * _quaternion[0] + 
                       _quaternion[1] * _quaternion[1] + 
                       _quaternion[2] * _quaternion[2] + 
                       _quaternion[3] * _quaternion[3]);
    
    if (qNorm < 0.0001) return;
    
    final q0 = _quaternion[0] / qNorm;
    final q1 = _quaternion[1] / qNorm;
    final q2 = _quaternion[2] / qNorm;
    final q3 = _quaternion[3] / qNorm;

    // ジャイロスコープによる姿勢更新
    final qDot0 = 0.5 * (-q1 * _gyroX - q2 * _gyroY - q3 * _gyroZ);
    final qDot1 = 0.5 * (q0 * _gyroX + q2 * _gyroZ - q3 * _gyroY);
    final qDot2 = 0.5 * (q0 * _gyroY - q1 * _gyroZ + q3 * _gyroX);
    final qDot3 = 0.5 * (q0 * _gyroZ + q1 * _gyroY - q2 * _gyroX);

    // 加速度センサーと磁気センサーによる補正
    // 重力方向の正規化
    final accNorm = sqrt(_accX * _accX + _accY * _accY + _accZ * _accZ);
    if (accNorm > 0.0001) {
      final ax = _accX / accNorm;
      final ay = _accY / accNorm;
      final az = _accZ / accNorm;

      // 磁気の正規化
      final magNorm = sqrt(_magX * _magX + _magY * _magY + _magZ * _magZ);
      if (magNorm > 0.0001) {
        final mx = _magX / magNorm;
        final my = _magY / magNorm;
        final mz = _magZ / magNorm;

        // 勾配降下アルゴリズムで補正項を計算
        final s0 = -2 * q2 * (2 * (q1 * q3 - q0 * q2) - ax) +
                   -2 * q3 * (2 * (q0 * q1 + q2 * q3) - ay);
        final s1 = 2 * q1 * (2 * (q1 * q3 - q0 * q2) - ax) +
                   2 * q0 * (2 * (q0 * q1 + q2 * q3) - ay) +
                   -4 * q1 * (1 - 2 * (q1 * q1 + q2 * q2) - az);
        final s2 = -2 * q0 * (2 * (q1 * q3 - q0 * q2) - ax) +
                   2 * q3 * (2 * (q0 * q1 + q2 * q3) - ay) +
                   -4 * q2 * (1 - 2 * (q1 * q1 + q2 * q2) - az);
        final s3 = 2 * q1 * (2 * (q1 * q3 - q0 * q2) - ax) +
                   2 * q2 * (2 * (q0 * q1 + q2 * q3) - ay);

        // 正規化
        final sNorm = sqrt(s0 * s0 + s1 * s1 + s2 * s2 + s3 * s3);
        if (sNorm > 0.0001) {
          // 補正項を適用
          _quaternion[0] = q0 + (qDot0 - _beta * s0 / sNorm) * dt;
          _quaternion[1] = q1 + (qDot1 - _beta * s1 / sNorm) * dt;
          _quaternion[2] = q2 + (qDot2 - _beta * s2 / sNorm) * dt;
          _quaternion[3] = q3 + (qDot3 - _beta * s3 / sNorm) * dt;
        } else {
          _quaternion[0] = q0 + qDot0 * dt;
          _quaternion[1] = q1 + qDot1 * dt;
          _quaternion[2] = q2 + qDot2 * dt;
          _quaternion[3] = q3 + qDot3 * dt;
        }
      }
    }

    // クォータニオンから姿勢角を計算
    _calculateEulerAngles();
  }

  /// クォータニオンからオイラー角を計算
  void _calculateEulerAngles() {
    final q0 = _quaternion[0];
    final q1 = _quaternion[1];
    final q2 = _quaternion[2];
    final q3 = _quaternion[3];

    // ロール（x軸周りの回転）
    _roll = atan2(2 * (q0 * q1 + q2 * q3), 1 - 2 * (q1 * q1 + q2 * q2)) * 180 / pi;

    // ピッチ（y軸周りの回転）
    final sinp = 2 * (q0 * q2 - q3 * q1);
    if (sinp.abs() >= 1) {
      _pitch = (pi / 2).sign * sinp * 180 / pi; // ±90度でクランプ
    } else {
      _pitch = asin(sinp) * 180 / pi;
    }

    // ヨー（z軸周りの回転） = 方位角
    _heading = atan2(2 * (q0 * q3 + q1 * q2), 1 - 2 * (q2 * q2 + q3 * q3)) * 180 / pi;
    
    // 0〜360度に正規化
    if (_heading < 0) _heading += 360;
  }

  /// 拡張カルマンフィルタで状態を更新
  void updateWithMeasurement(double measuredHeading, double measuredDistance, double dt, {double confidence = 0.5}) {
    // 予測ステップ
    // 状態: [heading, velocity, x, y]
    final predicted = List<double>.from(_stateEstimate);
    
    // 運動モデル（等速直線運動）
    final radHeading = _stateEstimate[0] * pi / 180;
    predicted[2] += _stateEstimate[1] * cos(radHeading) * dt; // x更新
    predicted[3] += _stateEstimate[1] * sin(radHeading) * dt; // y更新
    
    // プロセスノイズ（信頼度が高いほど小さく）
    final processNoiseFactor = 1.0 - (_sensorReliabilityScore / 200); // 0.5-1.0
    final processNoise = [
      [0.1 * processNoiseFactor, 0.0, 0.0, 0.0],
      [0.0, 0.5 * processNoiseFactor, 0.0, 0.0],
      [0.0, 0.0, 1.0 * processNoiseFactor, 0.0],
      [0.0, 0.0, 0.0, 1.0 * processNoiseFactor],
    ];
    
    // 共分散行列の更新
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) {
        _covarianceMatrix[i][j] += processNoise[i][j];
      }
    }
    
    // 測定更新ステップ
    // 測定ノイズ（信頼度confidence: 0-1で可変）
    // confidence低い（RSSI）→ノイズ大、confidence高い（GPS良好）→ノイズ小
    final headingNoise = 4.0 / (confidence + 0.1); // 4-40度
    final distanceNoise = 2.0 / (confidence + 0.1); // 2-20m
    
    final measurementNoise = [
      [headingNoise, 0.0],
      [0.0, distanceNoise],
    ];
    
    // カルマンゲインの計算（簡易版）
    final innovation = [
      measuredHeading - predicted[0],
      measuredDistance - sqrt(predicted[2] * predicted[2] + predicted[3] * predicted[3]),
    ];
    
    // 角度差を-180〜180に正規化
    if (innovation[0] > 180) innovation[0] -= 360;
    if (innovation[0] < -180) innovation[0] += 360;
    
    // 状態の更新（信頼度に応じたゲイン）
    final gain = confidence * 0.5; // 0-0.5
    _stateEstimate[0] = predicted[0] + gain * innovation[0]; // 方位角
    
    // 0〜360度に正規化
    if (_stateEstimate[0] < 0) _stateEstimate[0] += 360;
    if (_stateEstimate[0] >= 360) _stateEstimate[0] -= 360;
    
    debugPrint('EKF更新: heading=${_stateEstimate[0].toStringAsFixed(1)}°, distance=${measuredDistance.toStringAsFixed(1)}m, confidence=${(confidence * 100).toStringAsFixed(0)}%');
  }

  /// 歩数をリセット
  void resetStepCount() {
    _stepCount = 0;
    _estimatedX = 0.0;
    _estimatedY = 0.0;
    notifyListeners();
  }

  /// クリーンアップ
  void dispose() {
    _accelSubscription?.cancel();
    _gyroSubscription?.cancel();
    _magSubscription?.cancel();
    super.dispose();
  }
}
