import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../services/audio_service.dart';

class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  final OnAudioQuery audioQuery = OnAudioQuery();

  @override
  Widget build(BuildContext context) {
    if (AudioService.currentSong == null) {
      return const SizedBox();
    }

    return Container(
      height: 70,
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          QueryArtworkWidget(
            controller: audioQuery,
            id: AudioService.currentSong!.id,
            type: ArtworkType.AUDIO,
            artworkWidth: 50,
            artworkHeight: 50,
            nullArtworkWidget: const Icon(
              Icons.music_note,
              color: Colors.white,
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

                Text(
                  AudioService.currentSong!.artist ??
                      "Unknown Artist",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
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
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}