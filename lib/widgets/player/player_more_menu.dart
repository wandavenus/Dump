import 'package:flutter/material.dart';

import '../../services/audio/media3/media3_audio_player.dart';

import '../../models/local_song.dart';
import '../../services/audio_service.dart';
import 'player_scan_rg_sheet.dart';
import 'player_song_info_sheet.dart';

class PlayerMoreMenu extends StatelessWidget {
  final LocalSong song;

  const PlayerMoreMenu({super.key, required this.song});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
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
            case _PlayerMoreAction.shuffle:
              AudioService.toggleShuffle();
            case _PlayerMoreAction.loop:
              AudioService.cycleLoopMode();
            case _PlayerMoreAction.songInfo:
              _showSongInfo(context);
            case _PlayerMoreAction.scanRg:
              showScanRgSheet(context, song);
          }
        },
        itemBuilder: (context) {
          final state = AudioService.playbackState.value;
          return [
            _toggleItem(
              value: _PlayerMoreAction.shuffle,
              icon: Icons.shuffle_rounded,
              label: state.shuffleEnabled ? 'Shuffle On' : 'Shuffle Off',
              active: state.shuffleEnabled,
            ),
            _toggleItem(
              value: _PlayerMoreAction.loop,
              icon: _loopIcon(state.loopMode),
              label: 'Loop ${_loopLabel(state.loopMode)}',
              active: state.loopMode != LoopMode.off,
            ),
            const PopupMenuDivider(height: 4),
            const PopupMenuItem<_PlayerMoreAction>(
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
            const PopupMenuItem<_PlayerMoreAction>(
              value: _PlayerMoreAction.scanRg,
              child: Row(
                children: [
                  Icon(
                    Icons.graphic_eq_rounded,
                    color: Colors.white70,
                    size: 20,
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Scan ReplayGain',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ];
        },
      ),
    );
  }

  static PopupMenuItem<_PlayerMoreAction> _toggleItem({
    required _PlayerMoreAction value,
    required IconData icon,
    required String label,
    required bool active,
  }) {
    return PopupMenuItem<_PlayerMoreAction>(
      value: value,
      child: Row(
        children: [
          Icon(
            icon,
            color: active ? const Color(0xFFF92D48) : Colors.white70,
            size: 20,
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              color: active ? const Color(0xFFF92D48) : Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  static IconData _loopIcon(LoopMode mode) =>
      mode == LoopMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded;

  static String _loopLabel(LoopMode mode) => switch (mode) {
    LoopMode.off => 'Off',
    LoopMode.all => 'All',
    LoopMode.one => 'One',
  };

  void _showSongInfo(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder:
          (context) => FractionallySizedBox(
            heightFactor: 0.72,
            child: PlayerSongInfoSheet(song: song),
          ),
    );
  }
}

enum _PlayerMoreAction { shuffle, loop, songInfo, scanRg }
