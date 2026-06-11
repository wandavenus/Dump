import 'package:flutter/material.dart';

import '../../models/local_song.dart';
import 'player_hero_tags.dart';
import 'player_more_menu.dart';

class PlayerSongHeader extends StatelessWidget {
  final LocalSong song;

  const PlayerSongHeader({super.key, required this.song});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Hero(
                tag: PlayerHeroTags.title(song),
                flightShuttleBuilder: _titleFlightShuttleBuilder,
                child: Material(
                  type: MaterialType.transparency,
                  child: Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 24,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                song.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 18,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        PlayerMoreMenu(song: song),
      ],
    );
  }

  static Widget _titleFlightShuttleBuilder(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    return Material(
      type: MaterialType.transparency,
      child: FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: flightDirection == HeroFlightDirection.push
            ? (toHeroContext.widget as Hero).child
            : (fromHeroContext.widget as Hero).child,
      ),
    );
  }
}
