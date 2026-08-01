part of '../../library_sections.dart';

/// CustomScrollView for the Daftar Putar (Frequently Played) library tab.
///
/// Loads play-count data via [countsFuture] and sorts [songs] by play count
/// descending. Displays the results as a Windows-style tile grid.
class _FrequentSongsView extends StatefulWidget {
  const _FrequentSongsView({
    required this.songs,
    required this.countsFuture,
    required this.scroll,
    required this.titleHeader,
    required this.bottomClearance,
    required this.onPlay,
    required this.onLongPress,
  });

  final List<LocalSong> songs;
  final Future<Map<String, dynamic>> countsFuture;
  final ScrollController scroll;

  /// Pre-built title + divider widget (no search bar for this tab).
  final Widget titleHeader;
  final double bottomClearance;

  final void Function(List<LocalSong>, int) onPlay;
  final void Function(BuildContext, LocalSong, List<LocalSong>, int)
  onLongPress;

  @override
  State<_FrequentSongsView> createState() => _FrequentSongsViewState();
}

class _FrequentSongsViewState extends State<_FrequentSongsView> {
  late Future<List<Playlist>> _playlistsFuture;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _playlistsFuture = PlaylistService.getPlaylists();
  }

  Future<void> _createPlaylist() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.of(ctx).surface,
        title: Text(
          ctx.l10n.newPlaylist,
          style: TextStyle(color: AppColors.of(ctx).primaryLabel),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: AppColors.of(ctx).primaryLabel),
          decoration: InputDecoration(
            hintText: ctx.l10n.playlistNameHint,
            hintStyle: TextStyle(color: AppColors.of(ctx).secondaryLabel),
          ),
          onSubmitted: (value) => Navigator.pop(ctx, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ctx.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(ctx.l10n.create),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.isNotEmpty) {
      await PlaylistService.createPlaylist(name);
      if (mounted) {
        setState(() => _playlistsFuture = PlaylistService.getPlaylists());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Playlist>>(
      future: _playlistsFuture,
      builder: (context, snapshot) {
        final playlists = (snapshot.data ?? const <Playlist>[])
            .where((p) => p.name.toLowerCase().contains(_filter))
            .toList();
        final c = AppColors.of(context);
        return CustomScrollView(
          controller: widget.scroll,
          slivers: [
            SliverToBoxAdapter(child: widget.titleHeader),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: TextField(
                  onChanged: (value) =>
                      setState(() => _filter = value.toLowerCase()),
                  style: TextStyle(color: c.primaryLabel),
                  decoration: InputDecoration(
                    hintText: context.l10n.searchInPlaylists,
                    hintStyle: TextStyle(color: c.secondaryLabel),
                    filled: true,
                    fillColor: c.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: Icon(
                      CupertinoIcons.search,
                      color: c.secondaryLabel,
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: GestureDetector(
                onTap: _createPlaylist,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 16, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          CupertinoIcons.plus,
                          color: Color(0xFFF92D48),
                          size: 36,
                        ),
                      ),
                      const SizedBox(width: 20),
                      Text(
                        '${context.l10n.newPlaylistDialogTitle}...',
                        style: const TextStyle(
                          color: Color(0xFFF92D48),
                          fontSize: 17,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: Divider(height: 1, thickness: 0.5)),
            if (playlists.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 148),
                  child: _EmptyPlaylists(onCreate: _createPlaylist),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, widget.bottomClearance),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => ListTile(
                      title: Text(
                        playlists[index].name,
                        style: TextStyle(color: c.primaryLabel),
                      ),
                      subtitle: Text(
                        '${playlists[index].songIds.length} ${context.l10n.songs}',
                        style: TextStyle(color: c.secondaryLabel),
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<Widget>(
                          builder: (_) =>
                              PlaylistPage.user(playlist: playlists[index]),
                        ),
                      ),
                    ),
                    childCount: playlists.length,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _EmptyPlaylists extends StatelessWidget {
  const _EmptyPlaylists({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.l10n.noPlaylistsCreated,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.of(context).primaryLabel,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Anda dapat membuat daftar putar dari lagu '
            'di perpustakaan Anda atau dari katalog Apple Music.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.of(context).secondaryLabel,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: SizedBox(
              width: double.infinity,
              height: 61,
              child: FilledButton(
                onPressed: onCreate,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFF2948),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  context.l10n.newPlaylistDialogTitle,
                  style: const TextStyle(fontSize: 20),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
