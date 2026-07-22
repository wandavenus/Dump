import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/local_song.dart';
import '../services/audio_service.dart';
import '../services/log_service.dart';

/// Shared "Putar" / "Acak" action buttons — used consistently across
/// Song List, Album List (Library), Album Detail, and Artist Detail.
class PlayShuffleButtons extends StatelessWidget {
  const PlayShuffleButtons({super.key, required this.songs, this.topPadding = 16});

  final List<LocalSong> songs;

  /// Jarak dari elemen di atasnya (default 16, dipakai di Album/Artist Detail).
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, topPadding, 16, 0),
      child: Row(
        children: [
          _ActionButton(
            icon: CupertinoIcons.play_fill,
            label: 'Putar',
            onTap: () async {
              if (songs.isEmpty) return;
              try {
                await AudioService.playSongAt(playlist: songs, index: 0);
              } catch (e) {
                LogService.error('PlayShuffleButtons', 'play error: $e');
              }
            },
          ),
          const SizedBox(width: 8),
          _ActionButton(
            icon: CupertinoIcons.shuffle,
            label: 'Acak',
            onTap: () async {
              if (songs.isEmpty) return;
              try {
                if (!AudioService.shuffleEnabled) {
                  await AudioService.toggleShuffle();
                }
                final randomIndex = Random().nextInt(songs.length);
                await AudioService.playSongAt(
                    playlist: songs, index: randomIndex);
              } catch (e) {
                LogService.error('PlayShuffleButtons', 'shuffle error: $e');
              }
            },
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: const Color(0xFF1C1C1E),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: const Color(0xFFF92D48), size: 20),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFFF92D48),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
