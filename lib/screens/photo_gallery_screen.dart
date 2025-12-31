import 'dart:io';
import 'package:flutter/material.dart';
import 'package:monoc_locsaver/models/location_record.dart';
import 'package:monoc_locsaver/services/database_helper.dart';
import 'package:intl/intl.dart';

class PhotoGalleryScreen extends StatefulWidget {
  const PhotoGalleryScreen({super.key});

  @override
  State<PhotoGalleryScreen> createState() => _PhotoGalleryScreenState();
}

class _PhotoGalleryScreenState extends State<PhotoGalleryScreen> {
  List<LocationRecord> _photos = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    final records = await DatabaseHelper.instance.readAllLocations();
    setState(() {
      _photos = records.where((r) => r.imagePath != null).toList();
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('写真ギャラリー', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _photos.isEmpty
              ? const Center(
                  child: Text('写真がありません', style: TextStyle(color: Colors.grey)),
                )
              : _buildPhotoGrid(),
    );
  }

  Widget _buildPhotoGrid() {
    // 日付ごとにグループ化
    final grouped = <String, List<LocationRecord>>{};
    for (final photo in _photos) {
      final dateKey = DateFormat('yyyy-MM-dd').format(photo.timestamp);
      grouped.putIfAbsent(dateKey, () => []).add(photo);
    }

    final sortedKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      itemCount: sortedKeys.length,
      itemBuilder: (context, index) {
        final dateKey = sortedKeys[index];
        final photos = grouped[dateKey]!;
        final date = DateTime.parse(dateKey);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                DateFormat('yyyy年M月d日 (E)', 'ja').format(date),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: photos.length,
              itemBuilder: (context, i) {
                final photo = photos[i];
                return GestureDetector(
                  onTap: () => _showPhotoDetail(photo),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.file(
                      File(photo.imagePath!),
                      fit: BoxFit.cover,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  void _showPhotoDetail(LocationRecord photo) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PhotoDetailScreen(photo: photo, onUpdate: _loadPhotos),
      ),
    );
  }
}

class PhotoDetailScreen extends StatefulWidget {
  final LocationRecord photo;
  final VoidCallback onUpdate;

  const PhotoDetailScreen({super.key, required this.photo, required this.onUpdate});

  @override
  State<PhotoDetailScreen> createState() => _PhotoDetailScreenState();
}

class _PhotoDetailScreenState extends State<PhotoDetailScreen> {
  late LocationRecord _photo;

  @override
  void initState() {
    super.initState();
    _photo = widget.photo;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.white),
            onPressed: _deletePhoto,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 写真
            Image.file(
              File(_photo.imagePath!),
              width: double.infinity,
              fit: BoxFit.contain,
            ),
            // 情報
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 日時
                  Row(
                    children: [
                      const Icon(Icons.access_time, color: Colors.grey, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('yyyy年M月d日 HH:mm').format(_photo.timestamp),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 位置
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: Colors.grey, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_photo.latitude.toStringAsFixed(6)}, ${_photo.longitude.toStringAsFixed(6)}',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // メモ
                  const Text(
                    'メモ',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _editNote,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _photo.note?.isNotEmpty == true ? _photo.note! : 'タップしてメモを追加...',
                        style: TextStyle(
                          color: _photo.note?.isNotEmpty == true ? Colors.white : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // クイックタグ
                  const Text(
                    'クイックタグ',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildQuickTag('🍽️ 食事'),
                      _buildQuickTag('☕ カフェ'),
                      _buildQuickTag('🎉 イベント'),
                      _buildQuickTag('🏞️ 風景'),
                      _buildQuickTag('👥 友人と'),
                      _buildQuickTag('🛍️ 買い物'),
                      _buildQuickTag('⭐ お気に入り'),
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

  Widget _buildQuickTag(String tag) {
    final isSelected = _photo.note?.contains(tag) == true;
    return GestureDetector(
      onTap: () => _toggleTag(tag),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          border: Border.all(color: Colors.white),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          tag,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Future<void> _toggleTag(String tag) async {
    String newNote = _photo.note ?? '';
    if (newNote.contains(tag)) {
      newNote = newNote.replaceAll(tag, '').trim();
    } else {
      newNote = '$newNote $tag'.trim();
    }
    final updated = _photo.copyWith(note: newNote);
    await DatabaseHelper.instance.update(updated);
    setState(() {
      _photo = updated;
    });
    widget.onUpdate();
  }

  Future<void> _editNote() async {
    final controller = TextEditingController(text: _photo.note);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('メモを編集', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: '写真についてメモ...',
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
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('保存', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (result != null) {
      final updated = _photo.copyWith(note: result);
      await DatabaseHelper.instance.update(updated);
      setState(() {
        _photo = updated;
      });
      widget.onUpdate();
    }
  }

  Future<void> _deletePhoto() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('写真を削除', style: TextStyle(color: Colors.white)),
        content: const Text('この写真を削除しますか？', style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseHelper.instance.delete(_photo.id!);
      widget.onUpdate();
      Navigator.pop(context);
    }
  }
}
