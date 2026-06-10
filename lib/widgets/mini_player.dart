import 'package:flutter/material.dart';
import '../services/audio_service.dart';
import 'song_artwork.dart';

class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  @override
  void initState() {
    super.initState();
    AudioService.player.playerStateStream.listen((event) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (AudioService.currentSong == null) {
      return const SizedBox();
    }

    return GestureDetector(
      onTap: () {
        Navigator.pushNamed(
          context,
          '/player',
        );
      },
      child: Container(
        height: 55,
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(0),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: SizedBox(
                width: 50,
                height: 50,
                child: SongArtwork(
                  albumId: AudioService.currentSong!.albumId,
                  songId: AudioService.currentSong!.id,
                  path: AudioService.currentSong!.path,
                  size: 50,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AudioService.currentSong!.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () async {
                if (AudioService.player.playing) {
                  await AudioService.player.pause();
                } else {
                  await AudioService.player.play();
                }

                setState(() {});
              },
              icon: Icon(
                AudioService.player.playing
                    ? Icons.pause
                    : Icons.play_arrow,
                size: 34,
                color: Colors.white,
              ),
            ),
            IconButton(
              onPressed: () async {
                if (AudioService.currentPlaylist.isEmpty) return;

                if (AudioService.currentIndex <
                    AudioService.currentPlaylist.length - 1) {
                  AudioService.currentIndex++;

                  final nextSong = AudioService
                      .currentPlaylist[AudioService.currentIndex];

                  AudioService.currentSong = nextSong;

                  await AudioService.player.stop();

                  await AudioService.player.setAudioSource(
                    AudioService.createSource(nextSong),
                  );

                  await AudioService.player.play();

                  setState(() {});
                }
              },
              icon: const Icon(
                Icons.skip_next,
                size: 30,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
