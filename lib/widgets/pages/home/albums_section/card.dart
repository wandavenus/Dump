part of '../../home_sections.dart';

/// Tinggi artwork kartu album pada layout potret (skala 1.0).
const double _kAlbumArtworkHeight = 269;

/// Tinggi elemen non-artwork di dalam section carousel: caption satu baris,
/// jarak caption → kartu, dan padding vertikal ListView.
const double _kAlbumCardChromeHeight = 37;

class _AlbumCard extends StatefulWidget {
  final _AlbumGroup album;
  final String caption;

  /// Tinggi artwork kartu pada layout potret (skala penuh).
  static const double fullArtworkHeight = _kAlbumArtworkHeight;

  /// Tinggi blok info (nama album + artis) di bawah artwork.
  static const double infoHeight = 68;

  /// Tinggi caption + padding carousel di luar kartu.
  static const double chromeHeight = _kAlbumCardChromeHeight;

  /// Tinggi artwork kartu — menyusut mengikuti tinggi window.
  final double artworkHeight;

  const _AlbumCard({
    required this.album,
    required this.caption,
    required this.artworkHeight,
  });

  @override
  State<_AlbumCard> createState() => _AlbumCardState();
}

class _AlbumCardState extends State<_AlbumCard> {
  static const double _cardWidth = 260;
  static const double _cornerRadius = 10;

  static const Color _fallbackColor = Color(0xFF2B313A);

  Color _cardColor = _fallbackColor;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPaletteColor());
  }

  @override
  void didUpdateWidget(_AlbumCard old) {
    super.didUpdateWidget(old);
    if (old.album.coverSongId != widget.album.coverSongId) {
      unawaited(_loadPaletteColor());
    }
  }

  Future<void> _loadPaletteColor() async {
    final songId = widget.album.coverSongId;

    final cached = NativePaletteService.getSync(songId);
    if (cached != null) {
      if (mounted) {
        setState(() => _cardColor = _dominantColor(cached));
      }
      return;
    }

    final colors = await NativePaletteService.get(songId);
    if (!mounted) return;

    setState(() => _cardColor = _dominantColor(colors));
  }

  Color _dominantColor(List<Color> colors) {
    return colors.isNotEmpty ? colors.first : _fallbackColor;
  }

  @override
  Widget build(BuildContext context) {
    final album = widget.album;
    // Lebar kartu mengikuti tinggi artwork agar proporsi kartu tetap terjaga.
    final cardWidth =
        widget.artworkHeight * (_cardWidth / _AlbumCard.fullArtworkHeight);
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
              width: cardWidth,
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
                  width: cardWidth,
                  height: widget.artworkHeight + _AlbumCard.infoHeight,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: cardWidth,
                        height: widget.artworkHeight,
                        child: SongArtwork(
                          songId: album.coverSongId,
                          size: cardWidth,
                          borderRadius: BorderRadius.zero,
                          showBorder: false,
                        ),
                      ),
                      Container(
                        width: cardWidth,
                        height: _AlbumCard.infoHeight,
                        decoration: BoxDecoration(color: _cardColor),
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
