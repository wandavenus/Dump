part of '../browse_sections.dart';

// ─── Full Artwork Playlist Card ───────────────────────────────────────────────

class PlaylistCard extends StatelessWidget {
  final String name;
  final String subtitle;
  final List<int> artworkIds;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const PlaylistCard({
    super.key,
    required this.name,
    required this.subtitle,
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
        margin: const EdgeInsets.symmetric(
          horizontal: kPageLeftPadding,
          vertical: 6,
        ),
        height: 200,
        child: ArtworkHairlineBorder(
          borderRadius: BorderRadius.circular(14),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _ArtworkGrid(songIds: artworkIds),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.5),
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── 2×2 Artwork Grid ─────────────────────────────────────────────────────────

class _ArtworkGrid extends StatelessWidget {
  final List<int> songIds;

  const _ArtworkGrid({required this.songIds});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    if (songIds.isEmpty) {
      return ColoredBox(color: c.surface);
    }

    final ids = songIds.take(4).toList();

    if (ids.length == 1) {
      return _GridCell(songId: ids[0]);
    }

    final cells = List.generate(4, (i) {
      if (i < ids.length) return _GridCell(songId: ids[i]);
      return ColoredBox(color: c.surface2);
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
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final p = await ArtworkRepository.instance.getProvider(widget.songId);
      if (mounted) setState(() => _provider = p);
    } on Exception catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final p = _provider;
    if (p == null) {
      return ColoredBox(color: AppColors.of(context).surface2);
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
