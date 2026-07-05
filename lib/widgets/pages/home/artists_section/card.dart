part of '../../home_sections.dart';

class _ArtistCard extends StatelessWidget {
  final _ArtistGroup artist;
  const _ArtistCard({required this.artist});

  @override
  Widget build(BuildContext context) {
    const double avatarSize = 88.0;

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
              const SizedBox(height: 9),
              // ── Artist name ───────────────────────────────────────────────
              Text(
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
              const SizedBox(height: 3),
              // ── Song count — iOS gray ─────────────────────────────────────
              Text(
                '${artist.songs.length} lagu',
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'SF Pro Display',
                  color: Color(0xFF8E8E93),
                ),
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
