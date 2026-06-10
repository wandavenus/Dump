import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/media_store_service.dart';

class SongArtwork extends StatelessWidget {
  final int songId;
  final double size;
  final BorderRadius borderRadius;
  final BoxFit fit;

  const SongArtwork({
    super.key,
    required this.songId,
    this.size = 60,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final pixelRatio = MediaQuery.of(context).devicePixelRatio;
    final cacheSize = (size * pixelRatio).round();

    return RepaintBoundary(
      child: FutureBuilder<Uint8List?>(
        future: MediaStoreService.getArtwork(songId),
        builder: (context, snapshot) {
          final artwork = snapshot.data;
          if (artwork == null || artwork.isEmpty) {
            return _fallback();
          }

          return ClipRRect(
            borderRadius: borderRadius,
            child: Image.memory(
              artwork,
              width: size,
              height: size,
              fit: fit,
              gaplessPlayback: true,
              cacheWidth: cacheSize,
              cacheHeight: cacheSize,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, __, ___) => _fallback(),
            ),
          );
        },
      ),
    );
  }

  Widget _fallback() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        color: Colors.grey.shade900,
      ),
      child: const Icon(Icons.music_note),
    );
  }
}
