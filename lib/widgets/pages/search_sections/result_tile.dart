part of '../search_sections.dart';

class _SearchResultTile extends StatelessWidget {
  final LocalSong song;
  final List<LocalSong> playlist;
  final int index;

  const _SearchResultTile({
    required this.song,
    required this.playlist,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        await AudioService.playSongAt(playlist: playlist, index: index);
        PlayerPanelController.instance.open();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                        fontWeight: FontWeight.w500),
                  ),
                  Text(
                    '${song.artist} · ${song.album}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Color(0xFF8E8E93), fontSize: 13),
                  ),
                ],
              ),
            ),
            const Icon(Icons.play_arrow, color: Color(0xFF48484A), size: 20),
          ],
        ),
      ),
    );
  }
}

// ─── Category Grid ────────────────────────────────────────────────────────────
