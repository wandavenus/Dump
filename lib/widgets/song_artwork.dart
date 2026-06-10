import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../services/media_store_service.dart';

class SongArtwork extends StatefulWidget {
  final int albumId;
  final int? songId;
  final String? path;
  final double size;
  final double borderRadius;

  const SongArtwork({
    super.key,
    required this.albumId,
    this.songId,
    this.path,
    this.size = 60,
    this.borderRadius = 8,
  });

  @override
  State<SongArtwork> createState() => _SongArtworkState();
}

class _SongArtworkState extends State<SongArtwork> {
  Future<Uint8List?>? _artworkFuture;

  @override
  void initState() {
    super.initState();
    _updateArtworkFuture();
  }

  @override
  void didUpdateWidget(SongArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.albumId != widget.albumId ||
        oldWidget.songId != widget.songId ||
        oldWidget.path != widget.path) {
      _updateArtworkFuture();
    }
  }

  void _updateArtworkFuture() {
    _artworkFuture = MediaStoreService.getArtwork(
      widget.albumId,
      songId: widget.songId,
      path: widget.path,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _artworkFuture,
      builder: (context, snapshot) {
        final artwork = snapshot.data;

        if (artwork == null || artwork.isEmpty) {
          return _fallback();
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: Image.memory(
            artwork,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => _fallback(),
          ),
        );
      },
    );
  }

  Widget _fallback() {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        color: Colors.grey.shade900,
      ),
      child: Icon(
        Icons.music_note,
        size: widget.size * 0.45,
      ),
    );
  }
}
