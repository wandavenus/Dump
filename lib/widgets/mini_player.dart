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
      height: 60,
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E), 
 borderRadius: BorderRadius.circular(0),
      ),
      child: Row(
        children: [
          ClipRRect(
  borderRadius: BorderRadius.circular(3),
  child: QueryArtworkWidget(
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
        ],
      ),
     ),
   );
  }
}