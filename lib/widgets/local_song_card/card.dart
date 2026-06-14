part of '../local_song_card.dart';

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
