part of '../detail_sections.dart';

class AlbumHero extends StatelessWidget {
  const AlbumHero({super.key, required this.album});

  final LocalSong album;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      child: Column(
        children: [
          SongArtwork(
            songId: album.id,
            size: 300,
            borderRadius: BorderRadius.circular(15),
          ),
          const SizedBox(height: 20),
          Text(
            album.album,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Text(
            album.artist,
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.normal,
              color: Colors.red,
            ),
          ),
          const Text(
            'Local • Lossless',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Artist hero — artwork lagu sebagai latar belakang ─────────────────────
