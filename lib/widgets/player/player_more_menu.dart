import 'package:flutter/material.dart';

import '../../models/local_song.dart';
import 'player_song_info_sheet.dart';

class PlayerMoreMenu extends StatelessWidget {
  final LocalSong song;

  const PlayerMoreMenu({super.key, required this.song});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color.fromARGB(90, 100, 100, 100),
      ),
      child: PopupMenuButton<_PlayerMoreAction>(
        padding: EdgeInsets.zero,
        icon: const Icon(
          Icons.more_vert_rounded,
          color: Colors.white,
          size: 20,
        ),
        color: const Color(0xFF242426),
        elevation: 12,
        offset: const Offset(0, 42),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        onSelected: (action) {
          switch (action) {
            case _PlayerMoreAction.songInfo:
              _showSongInfo(context);
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem<_PlayerMoreAction>(
            value: _PlayerMoreAction.songInfo,
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: Colors.white70,
                  size: 20,
                ),
                SizedBox(width: 12),
                Text(
                  'Song Info',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showSongInfo(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.72,
        child: PlayerSongInfoSheet(song: song),
      ),
    );
  }
}

enum _PlayerMoreAction { songInfo }
