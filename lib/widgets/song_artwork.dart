import 'package:flutter/material.dart';

class SongArtwork extends StatelessWidget {
  final String? artworkUri;
  final double size;

  const SongArtwork({
    super.key,
    required this.artworkUri,
    this.size = 60,
  });

  @override
  Widget build(BuildContext context) {
    if (artworkUri == null || artworkUri!.isEmpty) {
      return _fallback();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        artworkUri!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(),
      ),
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
