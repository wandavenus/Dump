part of '../local_song_card.dart';

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
            width: 36, height: 4,
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
      builder: (_) => _SongInfoDialog(song: song),
    );
  }
}
