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
  late final Future<Uint8List?> _future;

  @override
  void initState() {
    super.initState();
    _future = MediaStoreService.getArtwork(widget.songId);
  }

  @override
  void didUpdateWidget(covariant SongArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.songId != widget.songId) {
      _future = MediaStoreService.getArtwork(widget.songId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pixelRatio = MediaQuery.of(context).devicePixelRatio;
    final cacheSize = (widget.size * pixelRatio).round();

    return RepaintBoundary(
      child: FutureBuilder<Uint8List?>(
        future: _future,
        builder: (context, snapshot) {
          final artwork = snapshot.data;
          if (artwork == null || artwork.isEmpty) {
            return _fallback();
          }

          return ClipRRect(
            borderRadius: widget.borderRadius,
            child: Image.memory(
              artwork,
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
        },
      ),
    );
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
