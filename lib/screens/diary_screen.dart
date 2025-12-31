import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:monoc_locsaver/models/location_record.dart';
import 'package:monoc_locsaver/services/database_helper.dart';
import 'package:monoc_locsaver/services/transport_detector.dart';
import 'package:intl/intl.dart';

class DiaryScreen extends StatefulWidget {
  final DateTime date;

  const DiaryScreen({super.key, required this.date});

  @override
  State<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends State<DiaryScreen> {
  List<LocationRecord> _records = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    final records = await DatabaseHelper.instance.readLocationsByDate(widget.date);
    setState(() {
      _records = records;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          DateFormat('yyyy年M月d日 (E)', 'ja').format(widget.date),
          style: const TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 自動生成された日記サマリー
                  _buildAutoSummary(),
                  const Divider(color: Colors.grey),
                  // 写真ギャラリー
                  if (_getPhotos().isNotEmpty) _buildPhotoGallery(),
                  // 訪れた場所
                  _buildVisitedPlaces(),
                  // タイムライン詳細
                  _buildDetailedTimeline(),
                ],
              ),
            ),
    );
  }

  Widget _buildAutoSummary() {
    final summary = _generateAutoSummary();
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              const Text(
                '今日のまとめ',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            summary,
            style: const TextStyle(color: Colors.white70, height: 1.6),
          ),
        ],
      ),
    );
  }

  String _generateAutoSummary() {
    if (_records.isEmpty) {
      return '記録がありません。';
    }

    final photos = _getPhotos();
    final stayPoints = _records.where((r) => r.isStayPoint == true).toList();
    final totalDistance = _calculateTotalDistance();

    // 移動手段の集計
    final transportModes = <String, int>{};
    for (final r in _records) {
      if (r.transportMode != null && r.transportMode != 'stationary') {
        transportModes[r.transportMode!] = (transportModes[r.transportMode!] ?? 0) + 1;
      }
    }

    // 最も多い移動手段
    String? mainTransport;
    if (transportModes.isNotEmpty) {
      mainTransport = transportModes.entries.reduce((a, b) => a.value > b.value ? a : b).key;
    }

    // 時間帯
    final firstRecord = _records.first;
    final lastRecord = _records.last;
    final startTime = DateFormat('H時mm分').format(firstRecord.timestamp);
    final endTime = DateFormat('H時mm分').format(lastRecord.timestamp);

    // 訪れた地点名をリスト化
    final visitedPlaceNames = stayPoints
        .where((r) => r.placeName != null && r.placeName!.isNotEmpty)
        .map((r) => r.placeName!)
        .toSet()
        .take(3)
        .toList();

    // 高速道路/鉄道使用の確認
    final usedHighway = _records.any((r) => r.isHighway == true);
    final usedRailway = _records.any((r) => r.isRailway == true);

    // サマリー生成
    final buffer = StringBuffer();

    buffer.write('$startTimeから$endTimeまで');
    if (mainTransport != null) {
      buffer.write('、主に${TransportDetector.getTransportLabel(mainTransport)}で');
    }
    buffer.write('、約${(totalDistance / 1000).toStringAsFixed(1)}km移動しました。');

    // 交通機関の特記事項
    if (usedHighway || usedRailway) {
      buffer.write('\n');
      if (usedRailway) {
        buffer.write('🚃 電車を利用');
      }
      if (usedHighway) {
        if (usedRailway) buffer.write('、');
        buffer.write('🛣️ 高速道路を利用');
      }
      buffer.write('しました。');
    }

    // 訪れた場所
    if (visitedPlaceNames.isNotEmpty) {
      buffer.write('\n📍 ${visitedPlaceNames.join('、')}');
      if (stayPoints.length > visitedPlaceNames.length) {
        buffer.write(' など${stayPoints.length}箇所');
      }
      buffer.write('に立ち寄りました。');
    } else if (stayPoints.isNotEmpty) {
      buffer.write('\n${stayPoints.length}箇所に立ち寄りました。');
    }

    if (photos.isNotEmpty) {
      buffer.write('\n📷 ${photos.length}枚の写真を撮影しました。');
    }

    return buffer.toString();
  }

  double _calculateTotalDistance() {
    double total = 0;
    for (int i = 1; i < _records.length; i++) {
      total += TransportDetector.calculateDistance(
        _records[i - 1].latitude,
        _records[i - 1].longitude,
        _records[i].latitude,
        _records[i].longitude,
      );
    }
    return total;
  }

  List<LocationRecord> _getPhotos() {
    return _records.where((r) => r.imagePath != null).toList();
  }

  Widget _buildPhotoGallery() {
    final photos = _getPhotos();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            '撮影した写真',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: photos.length,
            itemBuilder: (context, index) {
              final photo = photos[index];
              return GestureDetector(
                onTap: () => _showPhotoDetail(photo),
                child: Container(
                  width: 120,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(photo.imagePath!),
                          width: 120,
                          height: 120,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        bottom: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            DateFormat('HH:mm').format(photo.timestamp),
                            style: const TextStyle(color: Colors.white, fontSize: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildVisitedPlaces() {
    final stayPoints = _records.where((r) => r.isStayPoint == true).toList();
    if (stayPoints.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            '訪れた場所',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ...stayPoints.map((place) => _buildPlaceCard(place)),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildPlaceCard(LocationRecord place) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white24),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.location_on, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  place.placeName ?? '滞在地点',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                if (place.placeType != null)
                  Text(
                    place.placeType!,
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                Row(
                  children: [
                    Text(
                      '${DateFormat('HH:mm').format(place.timestamp)} · ${place.stayDurationMinutes ?? 0}分滞在',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
                if (place.address != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      place.address!.length > 30 
                          ? '${place.address!.substring(0, 30)}...' 
                          : place.address!,
                      style: const TextStyle(color: Colors.grey, fontSize: 10),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.grey, size: 20),
            onPressed: () => _editPlaceName(place),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedTimeline() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            '詳細タイムライン',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _records.length,
          itemBuilder: (context, index) {
            final record = _records[index];
            return _buildTimelineEntry(record, index);
          },
        ),
      ],
    );
  }

  Widget _buildTimelineEntry(LocationRecord record, int index) {
    final hasPhoto = record.imagePath != null;
    final isStay = record.isStayPoint == true;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 50,
            child: Text(
              DateFormat('HH:mm').format(record.timestamp),
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          Column(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: hasPhoto || isStay ? Colors.white : Colors.grey[700],
                  shape: BoxShape.circle,
                ),
              ),
              if (index < _records.length - 1)
                Container(
                  width: 1,
                  height: 30,
                  color: Colors.grey[700],
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _getEntryDescription(record),
              style: TextStyle(
                color: hasPhoto || isStay ? Colors.white : Colors.grey,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getEntryDescription(LocationRecord record) {
    if (record.imagePath != null) {
      return '📷 写真を撮影${record.note != null ? " - ${record.note}" : ""}';
    }
    if (record.isStayPoint == true) {
      return '📍 ${record.placeName ?? "滞在"}${record.stayDurationMinutes != null ? " (${record.stayDurationMinutes}分)" : ""}';
    }
    return '${TransportDetector.getTransportLabel(record.transportMode)}${record.speed != null ? " (${(record.speed! * 3.6).toStringAsFixed(0)} km/h)" : ""}';
  }

  void _showPhotoDetail(LocationRecord photo) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                Image.file(File(photo.imagePath!)),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('HH:mm').format(photo.timestamp),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  if (photo.note != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        photo.note!,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _editPhotoNote(photo);
                        },
                        icon: const Icon(Icons.edit, color: Colors.white, size: 16),
                        label: const Text('メモを追加', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _editPlaceName(LocationRecord place) {
    final controller = TextEditingController(text: place.placeName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('場所の名前', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: '例：カフェ、駅、公園...',
            hintStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              final updated = place.copyWith(placeName: controller.text);
              await DatabaseHelper.instance.update(updated);
              Navigator.pop(context);
              _loadRecords();
            },
            child: const Text('保存', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _editPhotoNote(LocationRecord photo) {
    final controller = TextEditingController(text: photo.note);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('写真メモ', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'この写真についてメモ...',
            hintStyle: TextStyle(color: Colors.grey),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              final updated = photo.copyWith(note: controller.text);
              await DatabaseHelper.instance.update(updated);
              Navigator.pop(context);
              _loadRecords();
            },
            child: const Text('保存', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
