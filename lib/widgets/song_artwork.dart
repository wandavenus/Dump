import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/media_store_service.dart';

class SongArtwork extends StatefulWidget {
  final int songId;
  final double size;
  final BorderRadius borderRadius;
  final BoxFit fit;

  const SongArtwork({
    super.key,
    required this.songId,
    this.size = 55,
    this.borderRadius = const BorderRadius.all(Radius.circular(5)),
    this.fit = BoxFit.cover,
  });

  @override
  State<SongArtwork> createState() => _SongArtworkState();
}

class _SongArtworkState extends State<SongArtwork> {
  // Menyimpan artwork yang sedang ditampilkan
  Uint8List? _currentArtwork;
  // ID yang sedang dimuat (untuk mencegah race condition)
  int _loadingId = -1;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadingId = widget.songId;
    _loadArtwork();
  }

  @override
  void didUpdateWidget(covariant SongArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.songId != widget.songId) {
      _loadingId = widget.songId;
      _loadArtwork();
    }
  }

  Future<void> _loadArtwork() async {
    if (_isLoading) return;
    _isLoading = true;

    final data = await MediaStoreService.getArtwork(_loadingId);

    // Hanya update jika ID masih sesuai (mencegah race condition)
    if (mounted && _loadingId == widget.songId) {
      setState(() {
        _currentArtwork = data;
        _isLoading = false;
      });
    } else {
      _isLoading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pixelRatio = MediaQuery.of(context).devicePixelRatio;
    final cacheSize = (widget.size * pixelRatio).round();

    // Jika artwork tersedia, tampilkan tanpa kedipan
    if (_currentArtwork != null && _currentArtwork!.isNotEmpty) {
      return ClipRRect(
        borderRadius: widget.borderRadius,
        child: Image.memory(
          _currentArtwork!,
          width: widget.size,
          height: widget.size,
          fit: widget.fit,
          gaplessPlayback: true,
          cacheWidth: cacheSize,
          cacheHeight: cacheSize,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => _fallback(),
        ),
      );
    }

    // Fallback jika tidak ada artwork
    return _fallback();
  }

  Widget _fallback() {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        borderRadius: widget.borderRadius,
        color: Colors.grey.shade900,
      ),
      child: const Icon(Icons.music_note),
    );
  }
}
