import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../models/local_song.dart';
import '../../pages/lyrics_page.dart';
import '../../services/audio_playback_state.dart';
import '../../services/audio_service.dart';

class PlayerSecondaryControls extends StatelessWidget {
  final LocalSong song;

  const PlayerSecondaryControls({
    super.key,
    required this.song,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: () => _openLyrics(context),
            icon: const Icon(CupertinoIcons.quote_bubble, size: 26),
            tooltip: 'Lirik',
          ),
          const SizedBox(width: 130),
          IconButton(
            onPressed: () => _showQueue(context),
            icon: const Icon(CupertinoIcons.list_bullet, size: 26),
            tooltip: 'Antrian',
          ),
        ],
      ),
    );
  }

  // ── Buka halaman lirik penuh layar ──────────────────────────────────────────

  void _openLyrics(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 380),
        pageBuilder: (_, __, ___) => LyricsPage(song: song),
        transitionsBuilder: (_, animation, __, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
            child: child,
          );
        },
      ),
    );
  }

  // ── Antrian putar ──────────────────────────────────────────────────────────

  void _showQueue(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.95,
          minChildSize: 0.4,
          expand: false,
          builder: (_, sc) => Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Antrian',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ValueListenableBuilder<AudioPlaybackState>(
                  valueListenable: AudioService.playbackState,
                  builder: (context, state, _) {
                    if (state.currentPlaylist.isEmpty) {
                      return const Center(
                        child: Text(
                          'Antrian kosong',
                          style: TextStyle(color: Color(0xFF8E8E93)),
                        ),
                      );
                    }
                    return ListView.builder(
                      controller: sc,
                      itemCount: state.currentPlaylist.length,
                      itemBuilder: (context, index) {
                        final s = state.currentPlaylist[index];
                        final isCurrent = index == state.currentIndex;
                        return ListTile(
                          onTap: () => AudioService.playFromCurrentQueue(index),
                          leading: isCurrent
                              ? const Icon(Icons.equalizer,
                                  color: Color(0xFFF92D48))
                              : null,
                          title: Text(
                            s.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color:
                                  isCurrent ? const Color(0xFFF92D48) : Colors.white,
                              fontWeight: isCurrent
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                          subtitle: Text(
                            s.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xFF8E8E93)),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
