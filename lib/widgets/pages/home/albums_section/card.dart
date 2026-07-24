part of '../../home_sections.dart';

class _AlbumCard extends StatefulWidget {
  final _AlbumGroup album;
  final String caption;
  const _AlbumCard({required this.album, required this.caption});

  @override
  State<_AlbumCard> createState() => _AlbumCardState();
}

class _AlbumCardState extends State<_AlbumCard> {
  // Dimensi diukur presisi dari referensi desain (kartu "Top Picks" style):
  // rasio lebar:tinggi-artwork:tinggi-info ≈ 250 : 258 : 68.
  static const double _cardWidth = 250;
  static const double _artworkHeight = 260;
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

    final cached = NativePaletteService.getSync(songId);
    if (cached != null) {
      if (mounted) setState(() => _bgColor = cached.length > 2 ? cached[2] : _fallbackColor);
      return;
    }

    final colors = await NativePaletteService.get(songId);
    if (!mounted) return;
    setState(() => _bgColor = colors.length > 2 ? colors[2] : _fallbackColor);
  }

  @override
  Widget build(BuildContext context) {
    final album = widget.album;
    return GestureDetector(
      onTap: () => Navigator.pushNamed(
        context,
        '/album',
        arguments: {'album': album.songs.first, 'songs': album.songs},
      ),
      child: Container(
        margin: const EdgeInsets.only(left: kCardMarginLeft, right: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _cardWidth,
              child: Text(
                widget.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color.fromARGB(255, 153, 153, 153),
                  fontSize: 15,
                ),
              ),
            ),
            const SizedBox(height: 7),

            // Kartu: artwork penuh di atas + blok warna solid berisi teks di bawah.
            // Hairline stroke membungkus seluruh kartu (bukan hanya artwork),
            // jadi border-nya ada di outer ClipRRect, dan SongArtwork di
            // dalamnya tidak menggambar border-nya sendiri (showBorder: false)
            // agar tidak dobel/ganjil di sambungan artwork-panel info.
            ArtworkHairlineBorder(
              borderRadius: BorderRadius.circular(_cornerRadius),
              child: ClipRRect(
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
                          showBorder: false,
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
                                fontWeight: FontWeight.w500,
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
            ),
          ],
        ),
      ),
    );
  }
}
