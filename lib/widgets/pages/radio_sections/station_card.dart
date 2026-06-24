part of '../radio_sections.dart';

// ─── Full Artwork Playlist Card ───────────────────────────────────────────────

class PlaylistCard extends StatelessWidget {
  final String name;
  final String subtitle;
  final IconData emptyIcon;
  final Color emptyIconColor;
  final List<int> artworkIds;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const PlaylistCard({
    super.key,
    required this.name,
    required this.subtitle,
    required this.emptyIcon,
    required this.emptyIconColor,
    required this.artworkIds,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        height: 200,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _ArtworkGrid(
                songIds: artworkIds,
                emptyIcon: emptyIcon,
                emptyIconColor: emptyIconColor,
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.9),
                    ],
                    stops: const [0.25, 1.0],
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 12, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.play_circle_filled,
                        color: Colors.white,
                        size: 48,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 2×2 Artwork Grid ─────────────────────────────────────────────────────────

class _ArtworkGrid extends StatelessWidget {
  final List<int> songIds;
  final IconData emptyIcon;
  final Color emptyIconColor;

  const _ArtworkGrid({
    required this.songIds,
    required this.emptyIcon,
    required this.emptyIconColor,
  });

  @override
  Widget build(BuildContext context) {
    if (songIds.isEmpty) {
      return Container(
        color: const Color(0xFF1C1C1E),
        child: Center(
          child: Icon(
            emptyIcon,
            size: 64,
            color: emptyIconColor.withOpacity(0.3),
          ),
        ),
      );
    }

    final ids = songIds.take(4).toList();

    if (ids.length == 1) {
      return _GridCell(songId: ids[0]);
    }

    final cells = List.generate(4, (i) {
      if (i < ids.length) return _GridCell(songId: ids[i]);
      return const ColoredBox(color: Color(0xFF2C2C2E));
    });

    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: cells[0]),
              Expanded(child: cells[1]),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(child: cells[2]),
              Expanded(child: cells[3]),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Grid cell — loads artwork and fills its parent ───────────────────────────

class _GridCell extends StatefulWidget {
  final int songId;
  const _GridCell({required this.songId});

  @override
  State<_GridCell> createState() => _GridCellState();
}

class _GridCellState extends State<_GridCell> {
  ImageProvider? _provider;

  @override
  void initState() {
    super.initState();
    _load();
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
      return const ColoredBox(color: Color(0xFF2C2C2E));
    }
    return Image(
      image: p,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
    );
  }
}
