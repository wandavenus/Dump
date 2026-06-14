part of 'detail_sections.dart';

class DetailTopBar extends StatelessWidget {
  const DetailTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 30, left: 10, right: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 15),
            padding: const EdgeInsets.all(5),
            child: InkWell(
              onTap: () => Navigator.of(context).pop(),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  size: 20, color: Colors.red),
            ),
          ),
          const Row(children: [
            _CircleIcon(icon: Icons.add),
            SizedBox(width: 18),
            _CircleIcon(icon: Icons.more_horiz)
          ]),
        ],
      ),
    );
  }
}

class _CircleIcon extends StatelessWidget {
  const _CircleIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(150),
        color: const Color.fromARGB(85, 79, 79, 79),
      ),
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Icon(icon, size: 20, color: Colors.red),
      ),
    );
  }
}

// ─── Album hero — pakai SongArtwork dari lagu lokal ────────────────────────

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
                fontSize: 30, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          Text(
            album.artist,
            style: const TextStyle(
                fontSize: 23, fontWeight: FontWeight.normal, color: Colors.red),
          ),
          const Text(
            'Local • Lossless',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
