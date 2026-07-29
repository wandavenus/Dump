part of '../browse_sections.dart';

// ─── "Musik Baru" — paged 3×2 grid ───────────────────────────────────────────
// Setiap halaman = 3 baris × 2 kolom = 6 item.
// Tiap sel = artwork kecil di kiri + judul & artis di kanan.
// Swipe horizontal berpindah ke 6 item berikutnya.

const int _kRowsPerPage = 3;
const int _kColsPerPage = 2;
const int _kItemsPerPage = _kRowsPerPage * _kColsPerPage; // 6

const double _kArtworkSize = 44.0;
const double _kColGap = 12.0;
const double _kRowGap = 10.0;

// Total tinggi area grid:
// 3 × 44 (artwork) + 2 × 10 (row gap) + 16×2 (padding atas bawah) = 196
const double _kGridHeight =
    _kRowsPerPage * _kArtworkSize +
    (_kRowsPerPage - 1) * _kRowGap +
    32.0;

class _NewMusicSection extends StatefulWidget {
  final List<LocalSong> songs;
  const _NewMusicSection({required this.songs});

  @override
  State<_NewMusicSection> createState() => _NewMusicSectionState();
}

class _NewMusicSectionState extends State<_NewMusicSection> {
  final _controller = PageController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.songs.isEmpty) return const SizedBox.shrink();

    final pageCount = (widget.songs.length / _kItemsPerPage).ceil();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ────────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.only(left: kPageLeftPadding, top: 10),
          child: Row(
            children: [
              Text(
                context.l10n.newMusicSection,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color.fromARGB(255, 186, 186, 186),
              ),
            ],
          ),
        ),

        // ── PageView grid ─────────────────────────────────────────────────────
        SizedBox(
          height: _kGridHeight,
          child: PageView.builder(
            controller: _controller,
            itemCount: pageCount,
            itemBuilder: (context, pageIndex) {
              final start = pageIndex * _kItemsPerPage;
              final pageSongs =
                  widget.songs.skip(start).take(_kItemsPerPage).toList();
              return _NewMusicPage(songs: pageSongs, allSongs: widget.songs, pageStart: start);
            },
          ),
        ),

      ],
    );
  }
}

// ─── Satu halaman = 3 baris × 2 kolom ────────────────────────────────────────

class _NewMusicPage extends StatelessWidget {
  final List<LocalSong> songs;
  final List<LocalSong> allSongs;
  final int pageStart;

  const _NewMusicPage({
    required this.songs,
    required this.allSongs,
    required this.pageStart,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: kPageLeftPadding,
        vertical: 16,
      ),
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          final cellW =
              (constraints.maxWidth - _kColGap) / _kColsPerPage;
          return Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(_kRowsPerPage, (row) {
              return Row(
                children: List.generate(_kColsPerPage, (col) {
                  final idx = row * _kColsPerPage + col;
                  return Padding(
                    padding: EdgeInsets.only(
                      left: col == 0 ? 0 : _kColGap,
                    ),
                    child: idx < songs.length
                        ? _NewMusicCell(
                            song: songs[idx],
                            allSongs: allSongs,
                            globalIndex: pageStart + idx,
                            width: cellW,
                          )
                        : SizedBox(width: cellW, height: _kArtworkSize),
                  );
                }),
              );
            }),
          );
        },
      ),
    );
  }
}

// ─── Satu sel = artwork kiri + judul/artis kanan ─────────────────────────────

class _NewMusicCell extends StatelessWidget {
  final LocalSong song;
  final List<LocalSong> allSongs;
  final int globalIndex;
  final double width;

  const _NewMusicCell({
    required this.song,
    required this.allSongs,
    required this.globalIndex,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    const artSize = _kArtworkSize;
    final textW = width - artSize - 10;

    return GestureDetector(
      onTap: () async {
        try {
          await AudioService.playSongAt(
            playlist: allSongs,
            index: globalIndex,
          );
        } on Exception catch (e) {
          LogService.error('NewMusicCell', 'playSongAt: $e');
        }
      },
      child: SizedBox(
        width: width,
        height: artSize,
        child: Row(
          children: [
            // Artwork
            ArtworkHairlineBorder(
              borderRadius: BorderRadius.circular(6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SongArtwork(
                  songId: song.id,
                  size: artSize,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Judul + artis + divider
            SizedBox(
              width: textW,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: c.primaryLabel,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: c.secondaryLabel,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Divider selebar judul (diukur dengan TextPainter)
                  LayoutBuilder(
                    builder: (ctx, constraints) {
                      final tp = TextPainter(
                        text: TextSpan(
                          text: song.title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        maxLines: 1,
                        textDirection: TextDirection.ltr,
                      )..layout(maxWidth: constraints.maxWidth);
                      return Container(
                        width: tp.width,
                        height: 0.5,
                        color: Colors.white.withValues(alpha: 0.25),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
