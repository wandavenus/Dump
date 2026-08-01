part of '../browse_sections.dart';

// ─── "Musik Baru" — carousel kolom 4×3 ──────────────────────────────────────
// Setiap halaman/kolom berisi 4 baris lagu.
// Tiga kolom pertama dapat digeser horizontal, dengan kolom berikutnya
// sengaja terlihat sebagian di sisi kanan seperti referensi desain.

const int _kRowsPerPage = 4;
const int _kItemsPerPage = _kRowsPerPage; // satu kolom = 4 item

const double _kArtworkSize = 44.0;
const double _kRowGap = 10.0;

// Total tinggi area carousel:
// 4 × 44 (artwork) + 3 × 10 (row gap) + 16×2 (padding atas bawah) = 240
const double _kGridHeight =
    _kRowsPerPage * _kArtworkSize + (_kRowsPerPage - 1) * _kRowGap + 32.0;

class _NewMusicSection extends StatefulWidget {
  final List<LocalSong> songs;
  const _NewMusicSection({required this.songs});

  @override
  State<_NewMusicSection> createState() => _NewMusicSectionState();
}

class _NewMusicSectionState extends State<_NewMusicSection> {
  // Slightly narrower pages expose the next column at the right edge,
  // matching the horizontal carousel treatment in the reference.
  final _controller = PageController(viewportFraction: 0.92);

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
            // Leave a preview of the next horizontal column visible.
            padEnds: false,
            itemCount: pageCount,
            itemBuilder: (context, pageIndex) {
              final start = pageIndex * _kItemsPerPage;
              final pageSongs = widget.songs
                  .skip(start)
                  .take(_kItemsPerPage)
                  .toList();
              return _NewMusicPage(
                songs: pageSongs,
                allSongs: widget.songs,
                pageStart: start,
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─── Satu halaman = satu kolom penuh berisi 4 baris ───────────────────────────

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
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(_kRowsPerPage, (row) {
          final idx = row;
          return songs.length > idx
              ? _NewMusicCell(
                  song: songs[idx],
                  allSongs: allSongs,
                  globalIndex: pageStart + idx,
                  width: double.infinity,
                  showDivider: idx < songs.length - 1,
                )
              : const SizedBox(width: double.infinity, height: _kArtworkSize);
        }),
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
  final bool showDivider;

  const _NewMusicCell({
    required this.song,
    required this.allSongs,
    required this.globalIndex,
    required this.width,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    const artSize = _kArtworkSize;

    return GestureDetector(
      onTap: () async {
        try {
          await AudioService.playSongAt(playlist: allSongs, index: globalIndex);
        } on Exception catch (e) {
          LogService.error('NewMusicCell', 'playSongAt: $e');
        }
      },
      child: SizedBox(
        width: width,
        height: artSize + (showDivider ? 7 : 0),
        child: Column(
          children: [
            SizedBox(
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
                  // Judul + artis
                  Expanded(
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
                        const SizedBox(height: 1),
                        Text(
                          song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: c.secondaryLabel,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    CupertinoIcons.ellipsis_vertical,
                    size: 20,
                    color: c.secondaryLabel,
                  ),
                ],
              ),
            ),
            if (showDivider) ...[
              const SizedBox(height: 6),
              // Divider membentang sampai area ikon ellipsis.
              Container(
                width: double.infinity,
                height: 0.5,
                color: c.separator,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
