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
  static const double _unfavoriteIconSize = 22;
  static const double _favoriteIconSize = 22;

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
          width: 30,
          height: 30,
          decoration: _isFavorite
              ? null
              : const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color.fromARGB(70, 100, 100, 100),
                ),
          child: _isFavorite
              ? const Icon(
                  CupertinoIcons.star_circle_fill,
                  color: Colors.white,
                  size: _favoriteIconSize,
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