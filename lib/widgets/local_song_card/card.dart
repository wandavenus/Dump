part of '../local_song_card.dart';

/// Card lagu lokal berukuran 170×170.
/// Tap = putar. Long press = contextual menu.
class LocalSongCard extends StatelessWidget {
  final LocalSong song;
  final List<LocalSong> playlist;
  final int index;
  final double artworkSize;

  const LocalSongCard({
    super.key,
    required this.song,
    required this.playlist,
    required this.index,
    this.artworkSize = 170,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        await AudioService.playSongAt(playlist: playlist, index: index);
      },
      onLongPress: () => _showContextMenu(context),
      child: Container(
        margin: const EdgeInsets.only(left: kCardMarginLeft, right: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            SongArtwork(
              songId: song.id,
              size: artworkSize,
              borderRadius: BorderRadius.circular(10),
            ),
            const SizedBox(height: 2.5),
            SizedBox(
              width: artworkSize - 5,
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
    showSongContextMenu(context, song: song, playlist: playlist, index: index);
  }
}
