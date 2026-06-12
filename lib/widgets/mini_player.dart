import 'package:flutter/material.dart';
import '../services/audio_playback_state.dart';
import '../models/local_song.dart';
import '../services/audio_service.dart';
import '../services/player_sheet_controller.dart';
import 'player/player_hero_tags.dart';
import 'song_artwork.dart';
import '../pages/music_player.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AudioPlaybackState>(
      valueListenable: AudioService.playbackState,
      builder: (context, playbackState, _) {
        final song = playbackState.currentSong;
        if (song == null) return const SizedBox.shrink();

        return GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const MusicPlayer(),
              ),
            );
          },
          child: Row(
            children: [
              Hero(
                tag: PlayerHeroTags.artwork(song),
                child: SongArtwork(songId: song.id, size: 46, borderRadius: BorderRadius.circular(3)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Hero(
                  tag: PlayerHeroTags.title(song),
                  child: Material(
                    type: MaterialType.transparency,
                    child: Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: () {
                  playbackState.isPlaying ? AudioService.pause() : AudioService.play();
                },
                icon: Icon(
                  playbackState.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 34,
                ),
              ),
              IconButton(
                onPressed: playbackState.currentIndex < playbackState.currentPlaylist.length - 1
                    ? () => AudioService.skipNext()
                    : null,
                icon: Icon(
                  Icons.skip_next,
                  color: playbackState.currentIndex < playbackState.currentPlaylist.length - 1 ? Colors.white : Colors.white24,
                  size: 30,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}