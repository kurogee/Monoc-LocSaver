import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:monoc_locsaver/models/buddy.dart';
import 'package:monoc_locsaver/services/nearby_service.dart';
import 'package:monoc_locsaver/services/sensor_fusion_service.dart';

/// 迷子探し画面 - バディの位置と方向を表示
class FinderScreen extends StatefulWidget {
  const FinderScreen({super.key});

  @override
  State<FinderScreen> createState() => _FinderScreenState();
}

class _FinderScreenState extends State<FinderScreen> with TickerProviderStateMixin {
  final NearbyService _nearbyService = NearbyService();
  final SensorFusionService _sensorFusion = SensorFusionService();
  
  // コンパスのヘディング（デバイスの向き）
  double _heading = 0;
  double _smoothHeading = 0; // 平滑化されたヘディング
  StreamSubscription<CompassEvent>? _compassSubscription;
  bool _useSensorFusion = true; // センサーフュージョンを使用するか
  
  // カルマンフィルタ用パラメータ（より高精度な方位推定）
  double _kalmanGain = 0.1;
  double _estimateError = 1.0;
  final double _measurementNoise = 4.0; // センサーノイズ
  final double _processNoise = 0.01; // プロセスノイズ
  
  // メディアンフィルタ用（外れ値除去）
  final List<double> _headingBuffer = [];
  static const int _bufferSize = 5;
  
  // アニメーション
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  
  // 名前編集
  final TextEditingController _nameController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    _initializeService();
    _setupCompass();
    _setupSensorFusion();
    _setupAnimation();
    _nameController.text = _nearbyService.myName;
  }

  void _initializeService() async {
    try {
      await _nearbyService.initialize();
      if (mounted) {
        _nameController.text = _nearbyService.myName;
        _nearbyService.addListener(_onServiceUpdate);
        setState(() {});
      }
    } catch (e) {
      debugPrint('サービス初期化エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('サービスの初期化に失敗しました'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _setupCompass() {
    try {
      final compassStream = FlutterCompass.events;
      if (compassStream == null) {
        debugPrint('コンパスが利用できません - センサーフュージョンに切り替えます');
        _useSensorFusion = true;
        return;
      }
      
      // センサーフュージョンを使用しない場合のみコンパスを使用
      if (!_useSensorFusion) {
        _compassSubscription = compassStream.listen(
          (event) {
            if (mounted && event.heading != null) {
              double newHeading = event.heading!;
              
              // メディアンフィルタで外れ値を除去
              _headingBuffer.add(newHeading);
              if (_headingBuffer.length > _bufferSize) {
                _headingBuffer.removeAt(0);
              }
              
              if (_headingBuffer.length >= 3) {
                // 中央値を取得（外れ値に強い）
                final sorted = List<double>.from(_headingBuffer)..sort();
                newHeading = sorted[sorted.length ~/ 2];
              }
              
              // カルマンフィルタで高精度に推定（障害物やノイズに強い）
              // 予測ステップ
              _estimateError += _processNoise;
              
              // 更新ステップ
              _kalmanGain = _estimateError / (_estimateError + _measurementNoise);
              
              // 角度の差分を計算（360度を考慮）
              var diff = newHeading - _smoothHeading;
              if (diff > 180) diff -= 360;
              if (diff < -180) diff += 360;
              
              // カルマンフィルタで推定値を更新
              _smoothHeading = (_smoothHeading + _kalmanGain * diff) % 360;
              if (_smoothHeading < 0) _smoothHeading += 360;
              
              // 誤差を更新
              _estimateError = (1 - _kalmanGain) * _estimateError;
              
              setState(() {
                _heading = _smoothHeading;
              });
            }
          },
          onError: (error) {
            debugPrint('コンパスエラー: $error');
          },
          cancelOnError: false,
        );
      }
    } catch (e) {
      debugPrint('コンパス初期化エラー: $e - センサーフュージョンに切り替えます');
      _useSensorFusion = true;
    }
  }
  
  void _setupSensorFusion() {
    try {
      _sensorFusion.initialize();
      _sensorFusion.addListener(() {
        if (mounted && _useSensorFusion) {
          setState(() {
            _heading = _sensorFusion.heading;
          });
        }
      });
      debugPrint('高精度センサーフュージョンが有効化されました');
    } catch (e) {
      debugPrint('センサーフュージョン初期化エラー: $e');
      _useSensorFusion = false;
    }
  }

  void _setupAnimation() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _compassSubscription?.cancel();
    _pulseController.dispose();
    _nearbyService.removeListener(_onServiceUpdate);
    _sensorFusion.removeListener(_onServiceUpdate);
    _nameController.dispose();
    super.dispose();
  }

  /// パーミッションをリクエスト
  Future<void> _requestPermissions() async {
    final granted = await _nearbyService.requestPermissions();
    if (!granted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bluetooth と位置情報の権限が必要です'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// 探索を開始/停止
  Future<void> _toggleSearching() async {
    try {
      if (!_nearbyService.hasPermissions) {
        await _requestPermissions();
        if (!_nearbyService.hasPermissions) return;
      }

      if (_nearbyService.isAdvertising || _nearbyService.isDiscovering) {
        await _nearbyService.stopAdvertising();
        await _nearbyService.stopDiscovery();
      } else {
        final advResult = await _nearbyService.startAdvertising();
        final discResult = await _nearbyService.startDiscovery();
        
        if (mounted && (!advResult || !discResult)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                !advResult && !discResult
                    ? '探索を開始できませんでした'
                    : !advResult
                        ? 'アドバタイズの開始に失敗しました'
                        : 'ディスカバリーの開始に失敗しました',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('探索トグルエラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('エラーが発生しました'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 名前を変更
  void _showNameDialog() {
    _nameController.text = _nearbyService.myName;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('表示名を設定', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: _nameController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'あなたの名前',
            hintStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white54),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              _nearbyService.setMyName(_nameController.text);
              Navigator.pop(context);
            },
            child: const Text('保存', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// 距離を読みやすい形式に変換（精度を考慮）
  String _formatDistance(double? meters, {bool showAccuracy = false}) {
    if (meters == null) return '---';
    
    String baseDistance;
    String accuracyNote = '';
    
    if (meters < 1) {
      baseDistance = '1m以内';
    } else if (meters < 10) {
      baseDistance = '${meters.toStringAsFixed(1)}m';
      if (showAccuracy) accuracyNote = ' (±2-5m)'; // 条件良好時
    } else if (meters < 30) {
      baseDistance = '${meters.round()}m';
      if (showAccuracy) accuracyNote = ' (±5-15m)';
    } else if (meters < 1000) {
      baseDistance = '${meters.round()}m';
      if (showAccuracy) accuracyNote = ' (推定)'; // 精度低下
    } else {
      baseDistance = '${(meters / 1000).toStringAsFixed(1)}km';
      if (showAccuracy) accuracyNote = ' (推定)';
    }
    
    return baseDistance + accuracyNote;
  }

  /// 方角を文字に変換
  String _getDirectionText(double? bearing) {
    if (bearing == null) return '';
    const directions = ['北', '北東', '東', '南東', '南', '南西', '西', '北西'];
    final index = ((bearing + 22.5) ~/ 45) % 8;
    return directions[index];
  }

  @override
  Widget build(BuildContext context) {
    final isSearching = _nearbyService.isAdvertising || _nearbyService.isDiscovering;
    final hasConnections = _nearbyService.connectedBuddies.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'バディを探す',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          // 精度モード切り替え
          IconButton(
            icon: Icon(
              _useSensorFusion ? Icons.sports_score : Icons.compass_calibration,
              color: _useSensorFusion ? Colors.green : Colors.orange,
            ),
            onPressed: () {
              setState(() {
                _useSensorFusion = !_useSensorFusion;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    _useSensorFusion 
                      ? '高精度モード (IMUセンサーフュージョン)'
                      : '通常モード (磁気センサー)',
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            tooltip: '精度モード切り替え',
          ),
          IconButton(
            icon: const Icon(Icons.person_outline, color: Colors.white),
            onPressed: _showNameDialog,
            tooltip: '名前を変更',
          ),
          if (hasConnections)
            IconButton(
              icon: const Icon(Icons.link_off, color: Colors.red),
              onPressed: () async {
                await _nearbyService.disconnectAll();
              },
              tooltip: 'すべて切断',
            ),
        ],
      ),
      body: Column(
        children: [
          // 自分の情報
          _buildMyInfoCard(),
          
          // 探索状態と操作ボタン
          _buildSearchControl(isSearching),
          
          // 接続済みバディ（レーダー表示）
          if (hasConnections)
            Expanded(child: _buildRadarView()),
          
          // 検出されたデバイス
          if (!hasConnections)
            Expanded(child: _buildDiscoveredList()),
        ],
      ),
    );
  }

  /// 自分の情報カード
  Widget _buildMyInfoCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(Icons.person, color: Colors.black),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _nearbyService.myName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'ID: ${_nearbyService.myId}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit, color: Colors.white54),
                onPressed: _showNameDialog,
              ),
            ],
          ),
          // PDR情報表示
          if (_useSensorFusion && _sensorFusion.stepCount > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      const Icon(Icons.directions_walk, color: Colors.green, size: 16),
                      const SizedBox(height: 4),
                      Text(
                        '${_sensorFusion.stepCount}歩',
                        style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      const Icon(Icons.explore, color: Colors.green, size: 16),
                      const SizedBox(height: 4),
                      Text(
                        '${_heading.toStringAsFixed(0)}°',
                        style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      const Icon(Icons.high_quality, color: Colors.green, size: 16),
                      const SizedBox(height: 4),
                      Text(
                        _useSensorFusion ? 'IMU' : 'MAG',
                        style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// センサー信頼度メーター
  Widget _buildReliabilityMeter() {
    final score = _sensorFusion.sensorReliabilityScore;
    Color color;
    String label;
    
    if (score >= 80) {
      color = Colors.green;
      label = '高精度';
    } else if (score >= 60) {
      color = Colors.lightGreen;
      label = '良好';
    } else if (score >= 40) {
      color = Colors.orange;
      label = '中程度';
    } else {
      color = Colors.red;
      label = '低精度';
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'センサー精度: $label',
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
            ),
            Text(
              '${score.toStringAsFixed(0)}',
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: score / 100,
            backgroundColor: Colors.grey[800],
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 4,
          ),
        ),
      ],
    );
  }

  /// 探索コントロール
  Widget _buildSearchControl(bool isSearching) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // パーミッション警告
          if (!_nearbyService.hasPermissions)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.orange),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Bluetooth と位置情報の権限が必要です',
                      style: TextStyle(color: Colors.orange),
                    ),
                  ),
                  TextButton(
                    onPressed: _requestPermissions,
                    child: const Text('許可', style: TextStyle(color: Colors.orange)),
                  ),
                ],
              ),
            ),
          
          // 探索ボタン
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _toggleSearching,
              icon: Icon(isSearching ? Icons.stop : Icons.search),
              label: Text(isSearching ? '探索を停止' : '周囲を探索'),
              style: ElevatedButton.styleFrom(
                backgroundColor: isSearching ? Colors.red : Colors.white,
                foregroundColor: isSearching ? Colors.white : Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          
          // 状態表示
          if (isSearching)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white54,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '同じアプリを使っている人を探しています...',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// レーダービュー（接続済みバディの方向を表示）
  Widget _buildRadarView() {
    return Container(
      margin: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Text(
            '接続中のバディ',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = min(constraints.maxWidth, constraints.maxHeight) - 32;
                return Center(
                  child: SizedBox(
                    width: size,
                    height: size,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // レーダー背景
                        _buildRadarBackground(size),
                        // バディマーカー
                        ..._nearbyService.connectedBuddies.map((buddy) {
                          return _buildBuddyMarker(buddy, size);
                        }),
                        // 中央の自分マーカー
                        _buildSelfMarker(),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          // バディリスト
          ..._nearbyService.connectedBuddies.map((buddy) => _buildBuddyInfoCard(buddy)),
        ],
      ),
    );
  }

  /// レーダー背景
  Widget _buildRadarBackground(double size) {
    return CustomPaint(
      size: Size(size, size),
      painter: RadarPainter(heading: _heading),
    );
  }

  /// バディマーカー
  Widget _buildBuddyMarker(Buddy buddy, double radarSize) {
    if (buddy.bearing == null) {
      return const SizedBox.shrink();
    }

    // デバイスの向きを考慮した相対角度
    final relativeAngle = (buddy.bearing! - _heading) * pi / 180;
    
    // 距離が不明な場合は方位のみ表示
    if (buddy.distance == null || buddy.distance! < 0) {
      // 方位のみ（レーダー外周）
      final radius = radarSize / 2 - 30;
      final x = radius * sin(relativeAngle);
      final y = -radius * cos(relativeAngle);
      
      return Transform.translate(
        offset: Offset(x, y),
        child: Icon(
          Icons.question_mark,
          color: Colors.grey,
          size: 20,
        ),
      );
    }
    
    // 距離に基づいて表示スケールを調整（近いほど大きく表示）
    double maxDistance = 50.0; // デフォルト50m
    Widget markerWidget;
    
    // 距離帯別UI切替
    if (buddy.distance! < 10) {
      // 0-10m: 点＋矢印（高精度）
      maxDistance = 10.0;
      markerWidget = _buildCloseRangeMarker(buddy);
    } else if (buddy.distance! < 30) {
      // 10-30m: 扇形（中精度）
      maxDistance = 30.0;
      markerWidget = _buildMidRangeMarker(buddy);
    } else {
      // 30m+: 方位のみ（低精度）
      maxDistance = 100.0;
      markerWidget = _buildFarRangeMarker(buddy);
    }
    
    final normalizedDistance = min(buddy.distance! / maxDistance, 1.0);
    final radius = (radarSize / 2 - 60) * normalizedDistance;
    
    final x = radius * sin(relativeAngle);
    final y = -radius * cos(relativeAngle);

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(x, y),
          child: markerWidget,
        );
      },
    );
  }
  
  /// 近距離マーカー（0-10m）
  Widget _buildCloseRangeMarker(Buddy buddy) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.scale(
          scale: _pulseAnimation.value * 0.85,
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.9),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withOpacity(0.6),
                  blurRadius: 15,
                  spreadRadius: 3,
                ),
              ],
            ),
            child: Center(
              child: Text(
                buddy.name.isNotEmpty ? buddy.name[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue, width: 1),
          ),
          child: Column(
            children: [
              Text(
                buddy.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                _formatDistance(buddy.distance),
                style: const TextStyle(
                  color: Colors.blue,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  /// 中距離マーカー（10-30m）
  Widget _buildMidRangeMarker(Buddy buddy) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.7),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: Center(
            child: Text(
              buddy.name.isNotEmpty ? buddy.name[0].toUpperCase() : '?',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _formatDistance(buddy.distance),
          style: const TextStyle(
            color: Colors.orange,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
  
  /// 遠距離マーカー（30m+）
  Widget _buildFarRangeMarker(Buddy buddy) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.circle,
          color: Colors.grey.withOpacity(0.5),
          size: 24,
        ),
        Text(
          _formatDistance(buddy.distance),
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 9,
          ),
        ),
      ],
    );
  }

  /// 自分マーカー
  Widget _buildSelfMarker() {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: const Icon(Icons.person, size: 16, color: Colors.black),
    );
  }

  /// バディ情報カード
  Widget _buildBuddyInfoCard(Buddy buddy) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                buddy.name.isNotEmpty ? buddy.name[0].toUpperCase() : '?',
                style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  buddy.name,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${_formatDistance(buddy.distance)} • ${_getDirectionText(buddy.bearing)}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          // 方向矢印
          if (buddy.bearing != null)
            Transform.rotate(
              angle: (buddy.bearing! - _heading) * pi / 180,
              child: const Icon(
                Icons.navigation,
                color: Colors.blue,
                size: 32,
              ),
            ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.red),
            onPressed: () => _nearbyService.disconnect(buddy.id),
            tooltip: '切断',
          ),
        ],
      ),
    );
  }

  /// 検出されたデバイスリスト
  Widget _buildDiscoveredList() {
    final buddies = _nearbyService.discoveredBuddies;
    
    if (buddies.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bluetooth_searching,
              size: 80,
              color: Colors.grey[700],
            ),
            const SizedBox(height: 16),
            Text(
              _nearbyService.isDiscovering
                  ? '周囲を探索中...'
                  : '探索を開始してください',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              '同じアプリを使っている人が\n近くにいると表示されます',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[700], fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: buddies.length,
      itemBuilder: (context, index) {
        final buddy = buddies[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.white24,
              child: Text(
                buddy.name.isNotEmpty ? buddy.name[0].toUpperCase() : '?',
                style: const TextStyle(color: Colors.white),
              ),
            ),
            title: Text(
              buddy.name,
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'タップして接続',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            trailing: const Icon(Icons.add_circle_outline, color: Colors.white),
            onTap: () async {
              final success = await _nearbyService.requestConnection(buddy.id);
              if (success && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${buddy.name} に接続リクエストを送信しました')),
                );
              }
            },
          ),
        );
      },
    );
  }
}

/// レーダー描画
class RadarPainter extends CustomPainter {
  final double heading;
  
  RadarPainter({required this.heading});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 背景円（グラデーション）
    final bgPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.grey[850]!,
          Colors.grey[900]!,
          Colors.black,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, bgPaint);

    // 同心円と距離ラベル
    final circlePaint = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    
    final distances = ['10m', '20m', '30m', '50m'];
    for (int i = 1; i <= 4; i++) {
      final r = radius * i / 4;
      canvas.drawCircle(center, r, circlePaint);
      
      // 距離ラベル
      final textPainter = TextPainter(
        text: TextSpan(
          text: distances[i - 1],
          style: const TextStyle(color: Colors.white38, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(center.dx + r - 20, center.dy + 4),
      );
    }

    // 十字線
    final crossPaint = Paint()
      ..color = Colors.white12
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      crossPaint,
    );
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      crossPaint,
    );

    // 北マーカー（赤い三角形）
    final northAngle = -heading * pi / 180;
    final northX = center.dx + (radius - 20) * sin(northAngle);
    final northY = center.dy - (radius - 20) * cos(northAngle);
    
    // 三角形を描画
    final trianglePaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;
    
    final path = Path();
    path.moveTo(northX, northY - 8); // 上
    path.lineTo(northX - 6, northY + 4); // 左下
    path.lineTo(northX + 6, northY + 4); // 右下
    path.close();
    canvas.drawPath(path, trianglePaint);
    
    // Nラベル
    final northTextPainter = TextPainter(
      text: const TextSpan(
        text: 'N',
        style: TextStyle(
          color: Colors.red,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(color: Colors.black, offset: Offset(1, 1), blurRadius: 2),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    northTextPainter.layout();
    northTextPainter.paint(canvas, Offset(northX - 6, northY + 8));
  }

  @override
  bool shouldRepaint(covariant RadarPainter oldDelegate) {
    return oldDelegate.heading != heading;
  }
}
