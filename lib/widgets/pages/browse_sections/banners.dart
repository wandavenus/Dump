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
        padding: const EdgeInsets.only(left: 6),
        itemCount: songs.length,
        itemBuilder: (context, index) {
          final song = songs[index];
          return Container(
            width: 370,
            margin: const EdgeInsets.only(left: kCardMarginLeft, right: kCardMarginLeft),
            child: Center(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.artist.toUpperCase(),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.of(context).secondaryLabel,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    song.title,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.normal,
                      color: AppColors.of(context).primaryLabel,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 0.5), 
                  Text(
                    song.album,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.normal,
                      color: AppColors.of(context).secondaryLabel,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  ArtworkHairlineBorder(
                    borderRadius: BorderRadius.circular(10),
                    child: ClipPath(
                      clipper: ShapeBorderClipper(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: _BannerArtwork(
                        songId: song.id,
                        width: 1080 / 3,
                        height: 720 / 3,
                      ),
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
        color: AppColors.of(context).surface,
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
