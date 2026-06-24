part of '../browse_sections.dart';

class BrowseBannerCarousel extends StatelessWidget {
  final List<LocalSong> songs;
  const BrowseBannerCarousel({super.key, required this.songs});

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) {
      return const SizedBox(
        height: 350,
        child: Center(child: SizedBox.shrink()),
      );
    }

    return SizedBox(
      height: 350,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: songs.length,
        itemBuilder: (context, index) {
          final song = songs[index];
          return Container(
            width: 370,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            child: Center(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.artist.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    song.title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.normal,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    song.album,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.normal,
                      color: Colors.grey,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  ClipPath(
                    clipper: ShapeBorderClipper(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    child: _BannerArtwork(
                      songId: song.id,
                      width: 1080 / 3,
                      height: 720 / 3,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Artwork loader untuk banner — fill ukuran persis seperti Image.asset lama ─

class _BannerArtwork extends StatefulWidget {
  final int songId;
  final double width;
  final double height;

  const _BannerArtwork({
    required this.songId,
    required this.width,
    required this.height,
  });

  @override
  State<_BannerArtwork> createState() => _BannerArtworkState();
}

class _BannerArtworkState extends State<_BannerArtwork> {
  ImageProvider? _provider;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _BannerArtwork old) {
    super.didUpdateWidget(old);
    if (old.songId != widget.songId) _load();
  }

  Future<void> _load() async {
    try {
      final p = await ArtworkRepository.instance.getProvider(widget.songId);
      if (mounted) setState(() => _provider = p);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final p = _provider;
    if (p == null) {
      return Container(
        width: widget.width,
        height: widget.height,
        color: const Color(0xFF1C1C1E),
        child: const Center(
          child: Icon(Icons.music_note, color: Colors.white24, size: 48),
        ),
      );
    }
    return Image(
      image: p,
      width: widget.width,
      height: widget.height,
      fit: BoxFit.cover,
      gaplessPlayback: true,
    );
  }
}

// ─── Browse section dengan local songs ────────────────────────────────────────
