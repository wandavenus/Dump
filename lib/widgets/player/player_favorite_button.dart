import 'dart:async' show unawaited;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../models/local_song.dart';
import '../../services/playlist_service.dart';

class PlayerFavoriteButton extends StatefulWidget {
  const PlayerFavoriteButton({super.key, required this.song});

  final LocalSong song;

  @override
  State<PlayerFavoriteButton> createState() => _PlayerFavoriteButtonState();
}

class _PlayerFavoriteButtonState extends State<PlayerFavoriteButton> {
  static const double _unfavoriteIconSize = 19;
  static const double _favoriteIconSize = 19;

  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadFavoriteState());
  }

  Future<void> _loadFavoriteState() async {
    final isFavorite = await PlaylistService.isFavorite(widget.song.id);
    if (mounted) setState(() => _isFavorite = isFavorite);
  }

  Future<void> _toggleFavorite() async {
    final isFavorite = await PlaylistService.toggleFavorite(widget.song.id);
    if (mounted) setState(() => _isFavorite = isFavorite);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: _isFavorite ? 'Remove from Favorites' : 'Add to Favorites',
      child: GestureDetector(
        onTap: _toggleFavorite,
        child: Container(
          width: 27,
          height: 27,
          decoration: _isFavorite
              ? null
              : const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color.fromARGB(50, 200, 200, 200),
                ),
          child: _isFavorite
              ? CustomPaint(
                  size: const Size.square(27),
                  painter: _FavoriteCutoutPainter(
                    iconSize: _favoriteIconSize,
                  ),
                )
              : const Icon(
                  CupertinoIcons.star,
                  color: Colors.white,
                  size: _unfavoriteIconSize,
                ),
        ),
      ),
    );
  }
}

class _FavoriteCutoutPainter extends CustomPainter {
  const _FavoriteCutoutPainter({required this.iconSize});

  final double iconSize;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.saveLayer(bounds, Paint());
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.shortestSide / 2,
      Paint()..color = Colors.white,
    );

    final textPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(CupertinoIcons.star_fill.codePoint),
        style: TextStyle(
          foreground: Paint()..blendMode = BlendMode.dstOut,
          fontSize: iconSize,
          fontFamily: CupertinoIcons.star_fill.fontFamily,
          package: CupertinoIcons.star_fill.fontPackage,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        (size.height - textPainter.height) / 2,
      ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FavoriteCutoutPainter oldDelegate) =>
      oldDelegate.iconSize != iconSize;
}
