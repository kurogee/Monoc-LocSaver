import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:monoc_locsaver/models/location_record.dart';
import 'package:monoc_locsaver/services/database_helper.dart';

/// 統計画面 - 移動距離、滞在場所、活動パターンの分析
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  DateTime _selectedMonth = DateTime.now();
  double _totalDistance = 0;
  int _totalPhotos = 0;
  int _totalRecords = 0;
  Map<String, int> _transportStats = {};
  List<_LocationCluster> _topLocations = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStatistics();
  }

  Future<void> _loadStatistics() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 選択月の全レコードを取得
      final startDate = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
      final endDate = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0, 23, 59, 59);
      
      final records = await DatabaseHelper.instance.readLocationsByDateRange(startDate, endDate);
      
      // 統計計算
      _calculateStatistics(records);
      
    } catch (e) {
      debugPrint('統計読み込みエラー: $e');
    }

    setState(() {
      _isLoading = false;
    });
  }

  void _calculateStatistics(List<LocationRecord> records) {
    _totalRecords = records.length;
    _totalPhotos = records.where((r) => r.imagePath != null).length;
    
    // 移動距離の計算
    double distance = 0;
    for (int i = 1; i < records.length; i++) {
      distance += _calculateDistance(
        records[i - 1].latitude,
        records[i - 1].longitude,
        records[i].latitude,
        records[i].longitude,
      );
    }
    _totalDistance = distance;

    // 交通手段の集計
    _transportStats = {};
    for (var record in records) {
      final transport = record.transportMode ?? 'unknown';
      _transportStats[transport] = (_transportStats[transport] ?? 0) + 1;
    }

    // 滞在場所のクラスタリング（よく訪れる場所）
    _topLocations = _clusterLocations(records);
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

  double _toRadians(double degrees) => degrees * pi / 180;

  /// 位置情報をクラスタリングして頻繁に訪れる場所を特定
  List<_LocationCluster> _clusterLocations(List<LocationRecord> records) {
    if (records.isEmpty) return [];

    // 簡易的なクラスタリング（半径50m以内を同一場所とみなす）
    List<_LocationCluster> clusters = [];
    const double clusterRadius = 50.0; // メートル

    for (var record in records) {
      bool added = false;
      
      // 既存クラスタに追加できるか確認
      for (var cluster in clusters) {
        final distance = _calculateDistance(
          cluster.centerLat,
          cluster.centerLng,
          record.latitude,
          record.longitude,
        );
        
        if (distance <= clusterRadius) {
          cluster.addRecord(record);
          added = true;
          break;
        }
      }
      
      // 新しいクラスタを作成
      if (!added) {
        clusters.add(_LocationCluster(
          centerLat: record.latitude,
          centerLng: record.longitude,
        )..addRecord(record));
      }
    }

    // 訪問回数でソート
    clusters.sort((a, b) => b.count.compareTo(a.count));
    return clusters.take(5).toList(); // トップ5のみ
  }

  Future<void> _selectMonth() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.white,
              onPrimary: Colors.black,
              surface: Colors.black,
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedMonth = DateTime(picked.year, picked.month, 1);
      });
      _loadStatistics();
    }
  }

  String _getTransportIcon(String transport) {
    switch (transport) {
      case 'walking':
        return '🚶';
      case 'running':
        return '🏃';
      case 'biking':
        return '🚴';
      case 'driving':
        return '🚗';
      case 'train':
        return '🚃';
      case 'stationary':
        return '📍';
      default:
        return '❓';
    }
  }

  String _getTransportLabel(String transport) {
    switch (transport) {
      case 'walking':
        return '徒歩';
      case 'running':
        return 'ランニング';
      case 'biking':
        return '自転車';
      case 'driving':
        return '車';
      case 'train':
        return '電車';
      case 'stationary':
        return '滞在';
      default:
        return '不明';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          '統計・分析',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month, color: Colors.white),
            onPressed: _selectMonth,
            tooltip: '月を選択',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 選択月の表示
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Text(
                        DateFormat('yyyy年 M月').format(_selectedMonth),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 基本統計
                  _buildSummaryCards(),
                  const SizedBox(height: 24),

                  // 交通手段の内訳
                  if (_transportStats.isNotEmpty) ...[
                    _buildSectionTitle('移動手段'),
                    const SizedBox(height: 12),
                    _buildTransportStats(),
                    const SizedBox(height: 24),
                  ],

                  // よく訪れる場所
                  if (_topLocations.isNotEmpty) ...[
                    _buildSectionTitle('よく訪れる場所 TOP 5'),
                    const SizedBox(height: 12),
                    _buildTopLocations(),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildSummaryCards() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            icon: Icons.directions_walk,
            value: '${(_totalDistance / 1000).toStringAsFixed(1)} km',
            label: '総移動距離',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            icon: Icons.photo_camera,
            value: '$_totalPhotos',
            label: '撮影枚数',
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 32),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTransportStats() {
    final total = _transportStats.values.fold(0, (sum, count) => sum + count);
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        children: _transportStats.entries.map((entry) {
          final percentage = (entry.value / total * 100).toStringAsFixed(1);
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text(
                          _getTransportIcon(entry.key),
                          style: const TextStyle(fontSize: 20),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _getTransportLabel(entry.key),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                    Text(
                      '$percentage%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: entry.value / total,
                    backgroundColor: Colors.grey[800],
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTopLocations() {
    return Column(
      children: _topLocations.asMap().entries.map((entry) {
        final index = entry.key;
        final cluster = entry.value;
        
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cluster.locationName ?? '場所 ${index + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${cluster.count}回訪問 • ${cluster.totalTimeMinutes}分滞在',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.location_on,
                color: Colors.grey[600],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// 位置情報のクラスタ（頻繁に訪れる場所）
class _LocationCluster {
  double centerLat;
  double centerLng;
  int count = 0;
  int totalTimeMinutes = 0;
  String? locationName;
  
  _LocationCluster({
    required this.centerLat,
    required this.centerLng,
  });

  void addRecord(LocationRecord record) {
    count++;
    // 簡易的な滞在時間推定（記録1件あたり5分と仮定）
    totalTimeMinutes += 5;
    
    // 中心座標を更新（平均）
    centerLat = (centerLat * (count - 1) + record.latitude) / count;
    centerLng = (centerLng * (count - 1) + record.longitude) / count;
  }
}
