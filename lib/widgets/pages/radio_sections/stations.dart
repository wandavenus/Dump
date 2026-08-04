// ignore_for_file: unawaited_futures

part of '../radio_sections.dart';

// ─── Data for smart playlist cards ───────────────────────────────────────────

// Smart card names are resolved at build time via context.l10n — see _SmartPlaylistCardWidget.
enum _SmartType { favorites }

final List<_SmartType> _smartCardTypes = [_SmartType.favorites];

// ─── Smart playlist card (loads artwork ids async) ────────────────────────────

class _SmartPlaylistCardWidget extends StatefulWidget {
  final int index;
  const _SmartPlaylistCardWidget({required this.index});

  @override
  State<_SmartPlaylistCardWidget> createState() =>
      _SmartPlaylistCardWidgetState();
}

class _SmartPlaylistCardWidgetState extends State<_SmartPlaylistCardWidget> {
  List<LocalSong> _songs = [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  String _resolveName(BuildContext context) {
    return switch (_smartCardTypes[widget.index]) {
      _SmartType.favorites => context.l10n.favoritesLabel,
    };
  }

  Future<void> _load() async {
    try {
      final ids = await PlaylistService.getFavoriteIds();
      final allSongs = await MediaStoreService.getSongs();
      final songMap = {for (final s in allSongs) s.id: s};
      final resolved = ids
          .where(songMap.containsKey)
          .map((id) => songMap[id]!)
          .toList();
      if (mounted) {
        setState(() => _songs = resolved);
        final previewIds = resolved.take(6).map((s) => s.id).toList();
        unawaited(ArtworkRepository.instance.prefetch(previewIds));
      }
    } on Exception catch (e) {
      LogService.error('SmartPlaylistCard', 'load error: $e');
    }
  }

  Future<void> _playSongAt(int index) async {
    try {
      await AudioService.playSongAt(playlist: _songs, index: index);
    } on Exception catch (e) {
      LogService.error('SmartPlaylistCard', 'playSongAt error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        kPageLeftPadding,
        8,
        kPageLeftPadding,
        8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Section header ────────────────────────────────────────────────
          Row(
            children: [
              Text(
                _resolveName(context),
                style: TextStyle(
                  color: c.primaryLabel,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ── 3×2 artwork grid ──────────────────────────────────────────────
          LayoutBuilder(
            builder: (ctx, constraints) {
              const crossCount = 3;
              const spacing = 15.0;
              final itemSize =
                  (constraints.maxWidth - spacing * (crossCount - 1)) /
                  crossCount;

              Widget cell(int i) {
                final hasSong = i < _songs.length;
                return GestureDetector(
                  onTap: hasSong ? () => unawaited(_playSongAt(i)) : null,
                  child: ArtworkHairlineBorder(
                    borderRadius: BorderRadius.circular(15),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: SizedBox(
                        width: itemSize,
                        height: itemSize,
                        child: hasSong
                            ? _GridCell(songId: _songs[i].id)
                            : ColoredBox(color: c.surface2),
                      ),
                    ),
                  ),
                );
              }

              return Column(
                children: [
                  Row(
                    children: [
                      cell(0),
                      const SizedBox(width: spacing),
                      cell(1),
                      const SizedBox(width: spacing),
                      cell(2),
                    ],
                  ),
                  const SizedBox(height: spacing),
                  Row(
                    children: [
                      cell(3),
                      const SizedBox(width: spacing),
                      cell(4),
                      const SizedBox(width: spacing),
                      cell(5),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─── User playlist card ───────────────────────────────────────────────────────

class _UserPlaylistCardWidget extends StatefulWidget {
  final Playlist playlist;
  final VoidCallback onDeleted;
  const _UserPlaylistCardWidget({
    super.key,
    required this.playlist,
    required this.onDeleted,
  });

  @override
  State<_UserPlaylistCardWidget> createState() =>
      _UserPlaylistCardWidgetState();
}

class _UserPlaylistCardWidgetState extends State<_UserPlaylistCardWidget> {
  List<int> _artworkIds = [];

  @override
  void initState() {
    super.initState();
    _artworkIds = widget.playlist.songIds.take(4).toList();
    unawaited(ArtworkRepository.instance.prefetch(_artworkIds));
  }

  void _open() {
    unawaited(
      Navigator.push(
        context,
        ZoomFadeRoute<void>(page: PlaylistPage.user(playlist: widget.playlist)),
      ).then((_) {
        // refresh after returning (songs may have been removed)
        widget.onDeleted();
      }),
    );
  }

  void _onLongPress() {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) => SwipeToDismissSheet(
          child: ColoredBox(
            color: AppColors.of(ctx).surface,
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.of(ctx).dragHandle,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: const Icon(
                      Icons.delete_outline,
                      color: Color(0xFFF92D48),
                    ),
                    title: Text(
                      ctx.l10n.deletePlaylist,
                      style: const TextStyle(color: Color(0xFFF92D48)),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await PlaylistService.deletePlaylist(widget.playlist.id);
                      widget.onDeleted();
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.playlist.songIds.length;
    return PlaylistCard(
      name: widget.playlist.name,
      subtitle: count == 0
          ? context.l10n.noSongsYet
          : context.l10n.songCount(count),
      artworkIds: _artworkIds,
      onTap: _open,
      onLongPress: _onLongPress,
    );
  }
}

// ─── User playlists section ───────────────────────────────────────────────────

class _UserPlaylistsSection extends StatefulWidget {
  const _UserPlaylistsSection();

  @override
  State<_UserPlaylistsSection> createState() => _UserPlaylistsSectionState();
}

class _UserPlaylistsSectionState extends State<_UserPlaylistsSection> {
  List<Playlist> _playlists = [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final list = await PlaylistService.getPlaylists();
    if (mounted) setState(() => _playlists = list);
  }

  Future<void> _createPlaylist() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final cc = AppColors.of(ctx);
        return AlertDialog(
          backgroundColor: cc.surface,
          title: Text(
            ctx.l10n.newPlaylist,
            style: TextStyle(color: cc.primaryLabel),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: TextStyle(color: cc.primaryLabel),
            decoration: InputDecoration(
              hintText: ctx.l10n.playlistNameHint,
              hintStyle: TextStyle(color: cc.secondaryLabel),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: cc.separator),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: cc.primaryLabel),
              ),
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                ctx.l10n.cancel,
                style: TextStyle(color: cc.secondaryLabel),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: Text(
                ctx.l10n.create,
                style: TextStyle(color: cc.primaryLabel),
              ),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (name != null && name.isNotEmpty) {
      await PlaylistService.createPlaylist(name);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            kPageLeftPadding,
            16,
            kPageLeftPadding,
            4,
          ),
          child: Row(
            children: [
              Text(
                context.l10n.myPlaylists,
                style: TextStyle(
                  color: c.primaryLabel,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _createPlaylist,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.add, color: c.primaryLabel, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        context.l10n.create,
                        style: TextStyle(color: c.primaryLabel, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_playlists.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                context.l10n.noPlaylists,
                style: TextStyle(color: c.secondaryLabel, fontSize: 14),
              ),
            ),
          )
        else
          ..._playlists.map(
            (p) => _UserPlaylistCardWidget(
              key: ValueKey(p.id),
              playlist: p,
              onDeleted: _load,
            ),
          ),
      ],
    );
  }
}
