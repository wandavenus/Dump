part of '../../home_sections.dart';

class _AlbumCard extends StatefulWidget {
  final _AlbumGroup album;
  const _AlbumCard({required this.album});

  @override
  State<_AlbumCard> createState() => _AlbumCardState();
}

class _AlbumCardState extends State<_AlbumCard> {
  // Dimensi diukur presisi dari referensi desain (kartu "Top Picks" style):
  // rasio lebar:tinggi-artwork:tinggi-info ≈ 250 : 258 : 68.
  static const double _cardWidth = 250;
  static const double _artworkHeight = 259;
  static const double _infoHeight = 68;
  static const double _cornerRadius = 10;

  static const Color _fallbackColor = Color(0xFF2B313A);

  Color _bgColor = _fallbackColor;

  @override
  void initState() {
    super.initState();
    _loadPaletteColor();
  }

  Future<void> _loadPaletteColor() async {
    final songId = widget.album.coverSongId;

    final cached = PaletteExtractor.getSync(songId);
    if (cached != null) {
      if (mounted) setState(() => _bgColor = cached[2]);
      return;
    }

    final bytes = await ArtworkRepository.instance.getBytes(songId);
    if (bytes == null || !mounted) return;

    final colors = await PaletteExtractor.get(songId, bytes);
    if (mounted) setState(() => _bgColor = colors[2]);
  }

  @override
  Widget build(BuildContext context) {
    final album = widget.album;
    return InkWell(
      onTap: () => Navigator.pushNamed(
        context,
        '/album',
        arguments: {'album': album.songs.first, 'songs': album.songs},
      ),
      child: Container(
        margin: const EdgeInsets.only(right: 10, left: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Album',
              style: TextStyle(
                color: Color.fromARGB(255, 153, 153, 153),
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 7),

            // Kartu: artwork penuh di atas + blok warna solid berisi teks di bawah.
            ClipRRect(
              borderRadius: BorderRadius.circular(_cornerRadius),
              child: SizedBox(
                width: _cardWidth,
                height: _artworkHeight + _infoHeight,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: _cardWidth,
                      height: _artworkHeight,
                      child: SongArtwork(
                        songId: album.coverSongId,
                        size: _cardWidth,
                        borderRadius: BorderRadius.zero,
                      ),
                    ),
                    Container(
                      width: _cardWidth,
                      height: _infoHeight,
                      color: _bgColor,
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center, 
    mainAxisAlignment: MainAxisAlignment.center,
    mainAxisSize: MainAxisSize.min,
    children: [
                          Text(
                            album.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center, 
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            album.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: Color(0xB3FFFFFF),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
