part of '../../home_sections.dart';

class _ArtistCard extends StatelessWidget {
  final _ArtistGroup artist;
  const _ArtistCard({required this.artist});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () =>
          Navigator.pushNamed(context, '/artist', arguments: artist.songs),
      child: Container(
        margin: const EdgeInsets.only(left: 6, right: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SongArtwork(
                songId: artist.coverSongId,
                size: 170,
                borderRadius: BorderRadius.zero,

    const double avatarSize = 150.0;

    return GestureDetector(
      onTap: () =>
          Navigator.pushNamed(context, '/artist', arguments: artist.songs),
      child: SizedBox(
        width: 106,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Square avatar with 3px radius ────────────────────────────
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SongArtwork(
                  songId: artist.coverSongId,
                  size: avatarSize,
                  borderRadius: BorderRadius.zero,
                ),
              ),
            ),
            const SizedBox(height: 2.5),
            SizedBox(
              width: 165,
              child: Text(
                artist.name,


                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'SF Pro Display',
                  height: 1.25,
                ),
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              // ── Song count — iOS gray ─────────────────────────────────────
              Text(
                '${artist.songs.length} lagu',
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'SF Pro Display',
                  color: Color(0xFF8E8E93),
                ),
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
              '${artist.songs.length} lagu',
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
}
