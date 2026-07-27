// ignore_for_file: unawaited_futures

part of '../radio_sections.dart';

// ─── Data for smart playlist cards ───────────────────────────────────────────

// Smart card names are resolved at build time via context.l10n — see _SmartPlaylistCardWidget.
enum _SmartType { favorites, recentlyPlayed, mostPlayed }

final _smartCardTypes = [
  _SmartType.favorites,
  _SmartType.recentlyPlayed,
  _SmartType.mostPlayed,
];

// ─── Smart playlist card (loads artwork ids async) ────────────────────────────

class _SmartPlaylistCardWidget extends StatefulWidget {
  final int index;
  const _SmartPlaylistCardWidget({required this.index});

  @override
  State<_SmartPlaylistCardWidget> createState() =>
      _SmartPlaylistCardWidgetState();
}

class _SmartPlaylistCardWidgetState extends State<_SmartPlaylistCardWidget> {
  List<int> _artworkIds = [];
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  SmartPlaylistType _resolveType() => switch (_smartCardTypes[widget.index]) {
    _SmartType.favorites      => SmartPlaylistType.favorites,
    _SmartType.recentlyPlayed => SmartPlaylistType.recentlyPlayed,
    _SmartType.mostPlayed     => SmartPlaylistType.mostPlayed,
  };

  String _resolveName(BuildContext context) {
    final l = context.l10n;
    return switch (_smartCardTypes[widget.index]) {
      _SmartType.favorites      => l.favoritesLabel,
      _SmartType.recentlyPlayed => l.recentlyPlayed,
      _SmartType.mostPlayed     => l.mostPlayedLabel,
    };
  }

  Future<void> _load() async {
    final type = _resolveType();
    try {
      List<int> ids;
      switch (type) {
        case SmartPlaylistType.favorites:
          ids = await PlaylistService.getFavoriteIds();
        case SmartPlaylistType.recentlyPlayed:
          ids = await HistoryService.getRecentlyPlayedIds();
        case SmartPlaylistType.mostPlayed:
          final counts = await HistoryService.getPlayCounts();
          final sorted = counts.entries.toList()
            ..sort((a, b) => (b.value as int).compareTo(a.value as int));
          ids = sorted
              .map((e) => int.tryParse(e.key) ?? 0)
              .where((id) => id != 0)
              .toList();
      }
      if (mounted) {
        setState(() {
          _count = ids.length;
          _artworkIds = ids.take(4).toList();
        });
        ArtworkRepository.instance.prefetch(_artworkIds);
      }
    } catch (_) {}
  }

  void _open() {
    Navigator.push(
      context,
      ZoomFadeRoute(
        page: PlaylistPage.smart(
          name: _resolveName(context),
          type: _resolveType(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PlaylistCard(
      name: _resolveName(context),
      subtitle: _count == 0 ? context.l10n.noSongsYet : context.l10n.songCount(_count),
      artworkIds: _artworkIds,
      onTap: _open,
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
    ArtworkRepository.instance.prefetch(_artworkIds);
  }

  void _open() {
    Navigator.push(
      context,
      ZoomFadeRoute(page: PlaylistPage.user(playlist: widget.playlist)),
    ).then((_) {
      // refresh after returning (songs may have been removed)
      widget.onDeleted();
    });
  }

  void _onLongPress() {
    showModalBottomSheet(
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
                  leading: const Icon(Icons.delete_outline, color: Color(0xFFF92D48)),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.playlist.songIds.length;
    return PlaylistCard(
      name: widget.playlist.name,
      subtitle: count == 0 ? context.l10n.noSongsYet : context.l10n.songCount(count),
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
    _load();
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
              child: Text(ctx.l10n.cancel, style: TextStyle(color: cc.secondaryLabel)),
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
          padding: const EdgeInsets.fromLTRB(kPageLeftPadding, 16, kPageLeftPadding, 4),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(20),
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
