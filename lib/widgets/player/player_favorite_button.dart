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
  static const double _favoriteIconSize = 30;

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
              ? const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                )
              : const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color.fromARGB(80, 100, 100, 100),
                ),
          child: Icon(
            CupertinoIcons.star,
            color: _isFavorite ? Colors.black : Colors.white,
            size: _isFavorite ? _favoriteIconSize : _unfavoriteIconSize,
          ),
        ),
      ),
    );
  }
}
