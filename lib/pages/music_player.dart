import 'package:flutter/material.dart';

import '../models/local_song.dart';
import '../services/audio_service.dart';
import '../widgets/player/player_background.dart';
import '../widgets/player/player_content.dart';
import '../widgets/player/player_empty_state.dart';

export '../widgets/player/player_hero_tags.dart';

class MusicPlayer extends StatefulWidget {
  const MusicPlayer({super.key});

  @override
  State<MusicPlayer> createState() => _MusicPlayerState();
}

class _MusicPlayerState extends State<MusicPlayer> {
  bool _handledRouteArguments = false;
  final String _lyrics = 'Loading lyrics...';

  @override
  void initState() {
    super.initState();
    AudioService.initialize();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_handledRouteArguments) return;
    _handledRouteArguments = true;
    _playRouteSongIfNeeded();
  }

  Future<void> _playRouteSongIfNeeded() async {
    final arguments = ModalRoute.of(context)?.settings.arguments;
    if (arguments is! Map<String, dynamic>) return;

    final rawIndex = arguments['index'];
    final rawSongs = arguments['songs'];
    if (rawIndex is! int || rawSongs is! List) return;

    final songs = rawSongs.whereType<LocalSong>().toList(growable: false);
    if (songs.isEmpty || rawIndex < 0 || rawIndex >= songs.length) return;

    try {
      await AudioService.playSongAt(playlist: songs, index: rawIndex);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error playing song: $error')),
      );
    }
  }

  String _formatTime(Duration duration) {
    final safeDuration = duration.isNegative ? Duration.zero : duration;
    final minutes = safeDuration.inMinutes.remainder(60);
    final seconds = safeDuration.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AudioPlaybackState>(
      valueListenable: AudioService.playbackState,
      builder: (context, playbackState, _) {
        final song = playbackState.currentSong;

        return Scaffold(
          backgroundColor: Colors.black,
          extendBodyBehindAppBar: true,
          body: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            child: Stack(
              fit: StackFit.expand,
              children: [
                AnimatedBlurredPlayerBackground(songId: song?.id ?? 0),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color.fromARGB(55, 0, 0, 0),
                        Color.fromARGB(230, 0, 0, 0),
                      ],
                    ),
                  ),
                ),
                SafeArea(
                  child: song == null
                      ? const PlayerEmptyState()
                      : PlayerContent(
                          song: song,
                          playbackState: playbackState,
                          formatTime: _formatTime,
                          lyrics: _lyrics,
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
