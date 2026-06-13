import 'package:flutter/material.dart';

import '../models/local_song.dart';
import '../services/audio_service.dart';
import 'player/player_panel_controller.dart';
import 'song_artwork.dart';

/// Card lagu lokal berukuran 170×170.
/// Tap = putar. Long press = contextual menu.
class LocalSongCard extends StatelessWidget {
  final LocalSong song;
  final List<LocalSong> playlist;
  final int index;

  const LocalSongCard({
    super.key,
    required this.song,
    required this.playlist,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        await AudioService.playSongAt(playlist: playlist, index: index);
        PlayerPanelController.instance.open();
      },
      onLongPress: () => _showContextMenu(context),
      child: Container(
        margin: const EdgeInsets.only(right: 10, left: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            SongArtwork(
              songId: song.id,
              size: 170,
              borderRadius: BorderRadius.circular(10),
            ),
            const SizedBox(height: 2.5),
            SizedBox(
              width: 165,
              child: Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.normal,
                  fontSize: 15,
                  color: Colors.white,
                ),
              ),
            ),
            Text(
              song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.normal,
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (_) => _SongContextMenu(song: song, playlist: playlist, index: index),
    );
  }
}

class _SongContextMenu extends StatelessWidget {
  final LocalSong song;
  final List<LocalSong> playlist;
  final int index;

  const _SongContextMenu({
    required this.song,
    required this.playlist,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 6),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                SongArtwork(
                  songId: song.id,
                  size: 48,
                  borderRadius: BorderRadius.circular(6),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF8E8E93),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 0.5, color: Color(0xFF38383A)),
          _ContextMenuItem(
            icon: Icons.play_arrow,
            label: 'Putar Sekarang',
            onTap: () async {
              Navigator.pop(context);
              await AudioService.playSongAt(playlist: playlist, index: index);
              PlayerPanelController.instance.open();
            },
          ),
          const Divider(height: 0.5, color: Color(0xFF38383A), indent: 52),
          _ContextMenuItem(
            icon: Icons.queue_music,
            label: 'Putar Selanjutnya',
            onTap: () {
              Navigator.pop(context);
              // Add to front of queue
              AudioService.addToQueueNext(song);
            },
          ),
          const Divider(height: 0.5, color: Color(0xFF38383A), indent: 52),
          _ContextMenuItem(
            icon: Icons.playlist_add,
            label: 'Tambah ke Antrian',
            onTap: () {
              Navigator.pop(context);
              AudioService.addToQueue(song);
            },
          ),
          const Divider(height: 0.5, color: Color(0xFF38383A), indent: 52),
          _ContextMenuItem(
            icon: Icons.info_outline,
            label: 'Informasi Lagu',
            onTap: () {
              Navigator.pop(context);
              _showSongInfo(context);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _showSongInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text('Informasi Lagu',
            style: TextStyle(color: Colors.white, fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoRow('Judul', song.title),
            _InfoRow('Artis', song.artist),
            _InfoRow('Album', song.album),
            _InfoRow('Durasi', _formatDuration(song.duration)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup',
                style: TextStyle(color: Color(0xFFF92D48))),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Color(0xFF8E8E93), fontSize: 11)),
          Text(value,
              style: const TextStyle(color: Colors.white, fontSize: 14)),
        ],
      ),
    );
  }
}

class _ContextMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ContextMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: 14),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}
