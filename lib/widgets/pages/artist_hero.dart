part of 'detail_sections.dart';

// ─── Artist hero — artwork lagu sebagai latar belakang ─────────────────────

class ArtistHero extends StatelessWidget {
  const ArtistHero({super.key, required this.songs});

  final List<LocalSong> songs;

  @override
  Widget build(BuildContext context) {
    final artistName = songs.first.artist;

    return SizedBox(
      height: 340,
      child: Stack(
        fit: StackFit.expand,
        children: [
          SongArtwork(
            songId: songs.first.id,
            size: 340,
            borderRadius: BorderRadius.zero,
            fit: BoxFit.cover,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.45),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DetailTopBar(),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 20),
                child: Text(
                  artistName,
                  style: const TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
