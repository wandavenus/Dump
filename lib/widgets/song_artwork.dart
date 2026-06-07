import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../services/media_store_service.dart';

class SongArtwork extends StatelessWidget {
  final int albumId;
  final double size;

  const SongArtwork({
    super.key,
    required this.albumId,
    this.size = 60,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: MediaStoreService.getArtwork(albumId),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          return _fallback();
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            snapshot.data!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _fallback(),
          ),
        );
      },
    );
  }

  Widget _fallback() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.grey.shade900,
      ),
      child: const Icon(Icons.music_note),
    );
  }
}
