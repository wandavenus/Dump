import 'dart:ui';

import 'package:flutter/material.dart';

import '../../models/local_song.dart';
import '../../services/audio_service.dart';
import '../song_artwork.dart';
import 'player_hero_tags.dart';
import 'player_progress_section.dart';
import 'player_secondary_controls.dart';
import 'player_song_header.dart';
import 'player_transport_controls.dart';

class PlayerContent extends StatelessWidget {
  final LocalSong song;
  final AudioPlaybackState playbackState;
  final String Function(Duration duration) formatTime;
  final String lyrics;

  const PlayerContent({
    super.key,
    required this.song,
    required this.playbackState,
    required this.formatTime,
    required this.lyrics,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final coverSize = (width - 44).clamp(260.0, 390.0).toDouble();

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
            child: Column(
              children: [
                const SizedBox(height: 18),
                Hero(
                  tag: PlayerHeroTags.artwork(song),
                  flightShuttleBuilder: _artworkFlightShuttleBuilder,
                  child: Material(
                    type: MaterialType.transparency,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(
                            color: Color.fromARGB(80, 0, 0, 0),
                            blurRadius: 28,
                            offset: Offset(0, 16),
                          ),
                        ],
                      ),
                      child: SongArtwork(
                        songId: song.id,
                        size: coverSize,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 42),
                PlayerSongHeader(song: song),
                const SizedBox(height: 22),
                PlayerProgressSection(formatTime: formatTime),
                const SizedBox(height: 28),
                PlayerTransportControls(playbackState: playbackState),
                const SizedBox(height: 32),
                PlayerSecondaryControls(lyrics: lyrics),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static Widget _artworkFlightShuttleBuilder(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Material(
          type: MaterialType.transparency,
          child: Transform.scale(
            scale: lerpDouble(
              0.98,
              1.0,
              Curves.easeOutCubic.transform(animation.value),
            )!,
            child: child,
          ),
        );
      },
      child: flightDirection == HeroFlightDirection.push
          ? (toHeroContext.widget as Hero).child
          : (fromHeroContext.widget as Hero).child,
    );
  }
}
