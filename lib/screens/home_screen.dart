import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:monoc_locsaver/models/location_record.dart';
import 'package:monoc_locsaver/services/database_helper.dart';
import 'package:monoc_locsaver/services/location_service.dart';
import 'package:monoc_locsaver/services/transport_detector.dart';
import 'package:monoc_locsaver/screens/diary_screen.dart';
import 'package:monoc_locsaver/screens/photo_gallery_screen.dart';
import 'package:monoc_locsaver/screens/finder_screen.dart';
import 'package:monoc_locsaver/screens/stats_screen.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final LocationService _locationService = LocationService();
  final MapController _mapController = MapController();
  List<LocationRecord> _records = [];
  bool _isTracking = false;
  DateTime _selectedDate = DateTime.now();
  String _currentTransport = 'stationary';

  @override
  void initState() {
    super.initState();
    _initLocationService();
    _loadRecords();
    _checkServiceStatus();
    _listenToServiceUpdates();
  }

  void _listenToServiceUpdates() {
    FlutterBackgroundService().on('update').listen((event) {
      if (event != null && mounted) {
        setState(() {
          _currentTransport = event['transport'] ?? 'stationary';
        });
        // 新しいデータがあればリロード
        if (_selectedDate.year == DateTime.now().year &&
            _selectedDate.month == DateTime.now().month &&
            _selectedDate.day == DateTime.now().day) {
          _loadRecords();
        }
      }
    });
  }

  Future<void> _checkServiceStatus() async {
    final isRunning = await _locationService.isRunning();
    setState(() {
      _isTracking = isRunning;
    });
  }

  Future<void> _initLocationService() async {
    final hasPermission = await _locationService.requestPermission();
    if (hasPermission) {
      // 初期位置へ移動
      final pos = await _locationService.getCurrentLocation();
      if (pos != null) {
        _mapController.move(LatLng(pos.latitude, pos.longitude), 15);
      }
    }
  }

  Future<void> _loadRecords() async {
    final records = await DatabaseHelper.instance.readLocationsByDate(_selectedDate);
    setState(() {
      _records = records;
    });
  }

  void _toggleTracking() async {
    if (_isTracking) {
      await _locationService.stopTracking();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('記録を停止しました')),
      );
      setState(() {
        _isTracking = false;
      });
      _loadRecords(); // 停止時に最新データを読み込み
    } else {
      await _locationService.startTracking();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('記録を開始しました')),
      );
      setState(() {
        _isTracking = true;
      });
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);

    if (pickedFile != null) {
      // アプリ内ストレージに保存
      final directory = await getApplicationDocumentsDirectory();
      final fileName = path.basename(pickedFile.path);
      final savedImage = await File(pickedFile.path).copy('${directory.path}/$fileName');

      // 現在位置を取得して保存
      final pos = await _locationService.getCurrentLocation();
      if (pos != null) {
        final record = LocationRecord(
          latitude: pos.latitude,
          longitude: pos.longitude,
          timestamp: DateTime.now(),
          imagePath: savedImage.path,
        );
        final saved = await DatabaseHelper.instance.create(record);
        _loadRecords();
        
        // 撮影後にクイックメモダイアログを表示
        if (mounted) {
          _showQuickMemoDialog(saved);
        }
      }
    }
  }

  void _showQuickMemoDialog(LocationRecord record) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(record.imagePath!),
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      '写真を保存しました',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'クイックタグ（タップで追加）',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildQuickTagButton(record, '🍽️ 食事'),
                  _buildQuickTagButton(record, '☕ カフェ'),
                  _buildQuickTagButton(record, '🎉 イベント'),
                  _buildQuickTagButton(record, '🏞️ 風景'),
                  _buildQuickTagButton(record, '👥 友人と'),
                  _buildQuickTagButton(record, '🛍️ 買い物'),
                  _buildQuickTagButton(record, '⭐ お気に入り'),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white),
                      ),
                      child: const Text('スキップ'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _showFullMemoDialog(record);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                      ),
                      child: const Text('メモを追加'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuickTagButton(LocationRecord record, String tag) {
    return GestureDetector(
      onTap: () async {
        String newNote = record.note ?? '';
        newNote = '$newNote $tag'.trim();
        final updated = record.copyWith(note: newNote);
        await DatabaseHelper.instance.update(updated);
        _loadRecords();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$tag を追加しました')),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(tag, style: const TextStyle(color: Colors.white, fontSize: 12)),
      ),
    );
  }

  void _showFullMemoDialog(LocationRecord record) {
    final controller = TextEditingController(text: record.note);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('メモを追加', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'この場所について...',
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
              final updated = record.copyWith(note: controller.text);
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

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
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
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _loadRecords();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 経路のポリライン作成
    final points = _records.map((r) => LatLng(r.latitude, r.longitude)).toList();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              'AppPartsIcons/map-svgrepo-com.svg',
              height: 24,
              colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
            ),
            const SizedBox(width: 8),
            const Text('Monoc LocSaver'),
          ],
        ),
        actions: [
          // 写真ギャラリーボタン
          IconButton(
            icon: SvgPicture.asset(
              'AppPartsIcons/album-svgrepo-com.svg',
              height: 24,
              colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const PhotoGalleryScreen()),
              );
            },
          ),
          // 日記ボタン
          IconButton(
            icon: SvgPicture.asset(
              'AppPartsIcons/memo-pencil-svgrepo-com.svg',
              height: 24,
              colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => DiaryScreen(date: _selectedDate)),
              );
            },
          ),
          // カレンダーボタン
          IconButton(
            icon: SvgPicture.asset(
              'AppPartsIcons/calendar-svgrepo-com.svg',
              height: 24,
              colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
            ),
            onPressed: () => _selectDate(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // 地図部分
          Expanded(
            flex: 3,
            child: FlutterMap(
              mapController: _mapController,
              options: const MapOptions(
                initialCenter: LatLng(35.6812, 139.7671), // 東京駅
                initialZoom: 15,
              ),
              children: [
                TileLayer(
                  // 白黒地図にするためのタイルプロバイダ（CartoDB Dark Matterなど）
                  // ここではOpenStreetMapの標準タイルをColorFilterで白黒にする
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.monoclocsaver',
                  tileBuilder: (context, widget, tile) {
                    return ColorFiltered(
                      colorFilter: const ColorFilter.matrix(<double>[
                        0.2126, 0.7152, 0.0722, 0, 0,
                        0.2126, 0.7152, 0.0722, 0, 0,
                        0.2126, 0.7152, 0.0722, 0, 0,
                        0,      0,      0,      1, 0,
                      ]),
                      child: widget,
                    );
                  },
                ),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: points,
                      strokeWidth: 4.0,
                      color: Colors.white,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: _records.where((r) => r.imagePath != null).map((r) {
                    return Marker(
                      point: LatLng(r.latitude, r.longitude),
                      width: 40,
                      height: 40,
                      child: GestureDetector(
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (_) => Dialog(
                              child: Image.file(File(r.imagePath!)),
                            ),
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white, width: 2),
                            shape: BoxShape.circle,
                            image: DecorationImage(
                              image: FileImage(File(r.imagePath!)),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                // 滞在地点マーカー（写真なし）
                MarkerLayer(
                  markers: _records.where((r) => r.isStayPoint == true && r.imagePath == null).map((r) {
                    return Marker(
                      point: LatLng(r.latitude, r.longitude),
                      width: 30,
                      height: 30,
                      child: GestureDetector(
                        onTap: () => _showRecordDetail(r),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black,
                            border: Border.all(color: Colors.white, width: 2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.location_on, color: Colors.white, size: 16),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          // 現在の移動状態表示
          if (_isTracking)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.grey[900],
              child: Row(
                children: [
                  Icon(_getTransportIcon(_currentTransport), color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    TransportDetector.getTransportLabel(_currentTransport),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const Spacer(),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('記録中', style: TextStyle(color: Colors.green, fontSize: 12)),
                ],
              ),
            ),
          // タイムライン部分
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.black,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left, color: Colors.white),
                          onPressed: () {
                            setState(() {
                              _selectedDate = _selectedDate.subtract(const Duration(days: 1));
                            });
                            _loadRecords();
                          },
                        ),
                        GestureDetector(
                          onTap: () => _selectDate(context),
                          child: Text(
                            DateFormat('yyyy/MM/dd (E)', 'ja').format(_selectedDate),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right, color: Colors.white),
                          onPressed: _selectedDate.isBefore(DateTime.now().subtract(const Duration(days: 1)))
                              ? () {
                                  setState(() {
                                    _selectedDate = _selectedDate.add(const Duration(days: 1));
                                  });
                                  _loadRecords();
                                }
                              : null,
                        ),
                      ],
                    ),
                  ),
                  // サマリー表示
                  if (_records.isNotEmpty) _buildSummary(),
                  Expanded(
                    child: _records.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.explore_off, color: Colors.grey, size: 48),
                                const SizedBox(height: 16),
                                const Text('記録がありません', style: TextStyle(color: Colors.grey)),
                                const SizedBox(height: 8),
                                if (!_isTracking)
                                  TextButton.icon(
                                    onPressed: _toggleTracking,
                                    icon: const Icon(Icons.play_arrow, color: Colors.white),
                                    label: const Text('記録を開始', style: TextStyle(color: Colors.white)),
                                  ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: _getTimelineItems().length,
                            itemBuilder: (context, index) {
                              final item = _getTimelineItems()[index];
                              return _buildTimelineItem(item, index);
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // 統計・分析ボタン
          FloatingActionButton.small(
            heroTag: 'stats',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const StatsScreen()),
              );
            },
            backgroundColor: Colors.purple[800],
            foregroundColor: Colors.white,
            tooltip: '統計・分析',
            child: const Icon(Icons.bar_chart, size: 20),
          ),
          const SizedBox(height: 8),
          // バディを探すボタン
          FloatingActionButton.small(
            heroTag: 'finder',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const FinderScreen()),
              );
            },
            backgroundColor: Colors.blue[800],
            foregroundColor: Colors.white,
            tooltip: 'バディを探す',
            child: const Icon(Icons.people, size: 20),
          ),
          const SizedBox(height: 8),
          // ギャラリーから選択ボタン
          FloatingActionButton.small(
            heroTag: 'gallery',
            onPressed: _pickFromGallery,
            backgroundColor: Colors.grey[800],
            foregroundColor: Colors.white,
            child: const Icon(Icons.photo_library, size: 20),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'camera',
            onPressed: _pickImage,
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            child: const Icon(Icons.camera_alt),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            heroTag: 'record',
            onPressed: _toggleTracking,
            backgroundColor: _isTracking ? Colors.grey : Colors.white,
            foregroundColor: Colors.black,
            child: Icon(_isTracking ? Icons.stop : Icons.play_arrow),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      final directory = await getApplicationDocumentsDirectory();
      final fileName = path.basename(pickedFile.path);
      final savedImage = await File(pickedFile.path).copy('${directory.path}/$fileName');

      final pos = await _locationService.getCurrentLocation();
      if (pos != null) {
        final record = LocationRecord(
          latitude: pos.latitude,
          longitude: pos.longitude,
          timestamp: DateTime.now(),
          imagePath: savedImage.path,
        );
        final saved = await DatabaseHelper.instance.create(record);
        _loadRecords();
        
        if (mounted) {
          _showQuickMemoDialog(saved);
        }
      }
    }
  }

  IconData _getTransportIcon(String? mode) {
    switch (mode) {
      case 'stationary':
        return Icons.location_on;
      case 'walking':
        return Icons.directions_walk;
      case 'cycling':
        return Icons.directions_bike;
      case 'driving':
        return Icons.directions_car;
      case 'train':
        return Icons.train;
      default:
        return Icons.navigation;
    }
  }

  Widget _buildSummary() {
    // 移動距離を計算
    double totalDistance = 0;
    for (int i = 1; i < _records.length; i++) {
      totalDistance += TransportDetector.calculateDistance(
        _records[i - 1].latitude,
        _records[i - 1].longitude,
        _records[i].latitude,
        _records[i].longitude,
      );
    }

    // 滞在地点数
    final stayPoints = _records.where((r) => r.isStayPoint == true).length;

    // 写真数
    final photos = _records.where((r) => r.imagePath != null).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildSummaryItem(Icons.straighten, '${(totalDistance / 1000).toStringAsFixed(1)} km'),
          _buildSummaryItem(Icons.location_on, '$stayPoints 地点'),
          _buildSummaryItem(Icons.camera_alt, '$photos 枚'),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: Colors.grey, size: 16),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }

  List<LocationRecord> _getTimelineItems() {
    // 連続する移動記録を1つにまとめ、滞在地点と写真は個別に表示
    final items = <LocationRecord>[];
    String? lastTransport;
    LocationRecord? moveStart;

    for (final record in _records) {
      if (record.imagePath != null || record.isStayPoint == true) {
        // 移動中だった場合は移動記録を追加
        if (moveStart != null) {
          items.add(moveStart);
          moveStart = null;
        }
        items.add(record);
        lastTransport = null;
      } else if (record.transportMode != null && record.transportMode != 'stationary') {
        // 移動中
        if (lastTransport != record.transportMode) {
          if (moveStart != null) {
            items.add(moveStart);
          }
          moveStart = record;
          lastTransport = record.transportMode;
        }
      }
    }

    if (moveStart != null) {
      items.add(moveStart);
    }

    return items;
  }

  Widget _buildTimelineItem(LocationRecord record, int index) {
    final isStay = record.isStayPoint == true;
    final hasPhoto = record.imagePath != null;

    return InkWell(
      onTap: () => _showRecordDetail(record),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 時間
            SizedBox(
              width: 50,
              child: Text(
                DateFormat('HH:mm').format(record.timestamp),
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
            // タイムラインのドット
            Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: isStay || hasPhoto ? Colors.white : Colors.transparent,
                    border: Border.all(color: Colors.white, width: 2),
                    shape: BoxShape.circle,
                  ),
                ),
                if (index < _getTimelineItems().length - 1)
                  Container(
                    width: 2,
                    height: 40,
                    color: Colors.grey[700],
                  ),
              ],
            ),
            const SizedBox(width: 12),
            // 内容
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _getTransportIcon(record.transportMode),
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          hasPhoto
                              ? '写真撮影'
                              : isStay
                                  ? record.placeName ?? '滞在'
                                  : TransportDetector.getTransportLabel(record.transportMode),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  // 住所表示（短縮）
                  if (record.address != null)
                    Text(
                      record.address!.length > 25 
                          ? '${record.address!.substring(0, 25)}...' 
                          : record.address!,
                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  if (isStay && record.stayDurationMinutes != null)
                    Text(
                      '${record.stayDurationMinutes}分滞在',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  if (!isStay && record.speed != null)
                    Row(
                      children: [
                        Text(
                          '${(record.speed! * 3.6).toStringAsFixed(1)} km/h',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        if (record.isHighway == true || record.isRailway == true) ...[
                          const SizedBox(width: 8),
                          Icon(
                            record.isRailway == true ? Icons.train : Icons.toll,
                            color: Colors.grey,
                            size: 12,
                          ),
                        ],
                      ],
                    ),
                ],
              ),
            ),
            // サムネイル
            if (hasPhoto)
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.file(
                  File(record.imagePath!),
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showRecordDetail(LocationRecord record) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          maxChildSize: 0.9,
          minChildSize: 0.3,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ハンドル
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[600],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // タイトル行
                  Row(
                    children: [
                      Icon(_getTransportIcon(record.transportMode), color: Colors.white),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          record.isStayPoint == true
                              ? record.placeName ?? '滞在地点'
                              : TransportDetector.getTransportLabel(record.transportMode),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // 施設タイプバッジ
                  if (record.placeType != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        record.placeType!,
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  // 日時
                  Text(
                    DateFormat('yyyy/MM/dd HH:mm').format(record.timestamp),
                    style: const TextStyle(color: Colors.grey),
                  ),
                  // 住所
                  if (record.address != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.place, color: Colors.grey, size: 16),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            record.address!,
                            style: const TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const Divider(color: Colors.grey, height: 24),
                  // 位置情報詳細
                  Text(
                    '緯度: ${record.latitude.toStringAsFixed(6)}',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  Text(
                    '経度: ${record.longitude.toStringAsFixed(6)}',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  if (record.speed != null)
                    Text(
                      '速度: ${(record.speed! * 3.6).toStringAsFixed(1)} km/h',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  if (record.stayDurationMinutes != null)
                    Text(
                      '滞在時間: ${record.stayDurationMinutes}分',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  // 道路情報
                  if (record.roadType != null || record.isHighway == true || record.isRailway == true) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.route, color: Colors.grey, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          _getRoadTypeLabel(record),
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                  // 写真
                  if (record.imagePath != null) ...[
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(record.imagePath!),
                        width: double.infinity,
                        height: 200,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ],
                  // メモ
                  if (record.note != null && record.note!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.note, color: Colors.grey, size: 16),
                              SizedBox(width: 4),
                              Text('メモ', style: TextStyle(color: Colors.grey, fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            record.note!,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  // アクションボタン
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          _mapController.move(
                            LatLng(record.latitude, record.longitude),
                            17,
                          );
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.map, color: Colors.white),
                        label: const Text('地図で表示', style: TextStyle(color: Colors.white)),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          await DatabaseHelper.instance.delete(record.id!);
                          _loadRecords();
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.delete, color: Colors.red),
                        label: const Text('削除', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _getRoadTypeLabel(LocationRecord record) {
    final parts = <String>[];
    if (record.isRailway == true) {
      parts.add('鉄道路線');
    }
    if (record.isHighway == true) {
      parts.add('高速道路');
    }
    if (record.roadType != null && parts.isEmpty) {
      // 道路タイプの日本語変換
      final roadLabels = {
        'motorway': '高速道路',
        'trunk': '国道',
        'primary': '主要道路',
        'secondary': '県道',
        'tertiary': '市道',
        'residential': '住宅街道路',
        'service': 'サービス道路',
        'cycleway': '自転車道',
        'footway': '歩道',
        'path': '小道',
        'railway': '鉄道',
      };
      parts.add(roadLabels[record.roadType] ?? record.roadType!);
    }
    return parts.isNotEmpty ? parts.join(' / ') : '一般道';
  }
}
