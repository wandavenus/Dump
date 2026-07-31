import 'dart:async' show unawaited;
import 'dart:math' as math;

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
    final layer = Offset.zero & size;
    canvas.saveLayer(layer, Paint());

    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.shortestSide / 2,
      Paint()..color = Colors.white,
    );

    final center = Offset(size.width / 2, size.height / 2);
    final radius = iconSize / 2;
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final angle = -math.pi / 2 + i * math.pi / 5;
      final pointRadius = i.isEven ? radius : radius * 0.42;
      final point = Offset(
        center.dx + pointRadius * math.cos(angle),
        center.dy + pointRadius * math.sin(angle),
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..blendMode = BlendMode.dstOut);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FavoriteCutoutPainter oldDelegate) =>
      oldDelegate.iconSize != iconSize;
}
