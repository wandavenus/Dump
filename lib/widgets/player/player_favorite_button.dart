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

  // Lazy initialization avoids constructing the cutout painter until the
  // favorited appearance is first shown, then reuses it across button rebuilds.
  late final _FavoriteCutoutPainter _favoritePainter =
      _FavoriteCutoutPainter(iconSize: _favoriteIconSize);

  bool _isFavorite = false;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadFavoriteState());
  }

  @override
  void didUpdateWidget(covariant PlayerFavoriteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id) {
      unawaited(_loadFavoriteState());
    }
  }

  Future<void> _loadFavoriteState() async {
    final generation = ++_loadGeneration;
    final songId = widget.song.id;
    final isFavorite = await PlaylistService.isFavorite(widget.song.id);
    if (!mounted || generation != _loadGeneration || songId != widget.song.id) {
      return;
    }
    setState(() => _isFavorite = isFavorite);
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
          width: 28,
          height: 28,
          decoration: _isFavorite
              ? null
              : const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color.fromARGB(50, 200, 200, 200),
                ),
          child: _isFavorite
              ? CustomPaint(
                  size: const Size.square(27),
                  painter: _favoritePainter,
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
  _FavoriteCutoutPainter({required this.iconSize})
    : _textPainter = _createTextPainter(iconSize);

  final double iconSize;
  final TextPainter _textPainter;

  static TextPainter _createTextPainter(double iconSize) {
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
    return textPainter;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.saveLayer(bounds, Paint());
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.shortestSide / 2,
      Paint()..color = Colors.white,
    );

    // Reuse the pre-laid-out glyph; paint() performs no TextPainter allocation
    // or text layout, preserving the original star cutout geometry.
    _textPainter.paint(
      canvas,
      Offset(
        (size.width - _textPainter.width) / 2,
        (size.height - _textPainter.height) / 2,
      ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FavoriteCutoutPainter oldDelegate) =>
      oldDelegate.iconSize != iconSize;
}
