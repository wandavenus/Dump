part of '../song_context_menu.dart';

// ─── _AddToPlaylistSheet ──────────────────────────────────────────────────────
//
// Bottom sheet for selecting an existing playlist or creating a new one.
// Opened from [_SongContextMenuState._showAddToPlaylist].

class _AddToPlaylistSheet extends StatefulWidget {
  final LocalSong song;
  final NavigatorState tabNavigator;
  const _AddToPlaylistSheet({required this.song, required this.tabNavigator});

  @override
  State<_AddToPlaylistSheet> createState() => _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends State<_AddToPlaylistSheet> {
  late Future<List<Playlist>> _future;

  @override
  void initState() {
    super.initState();
    _future = PlaylistService.getPlaylists();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return SwipeToDismissSheet(
      child: Material(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 6),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: c.dragHandle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    context.l10n.addToPlaylistTitle,
                    style: TextStyle(
                      color: c.primaryLabel,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Divider(
                height: 1,
                thickness: 0.5,
                color: c.separator,
                indent: 52,
              ),
              // Buat baru
              InkWell(
                onTap: () => _createNew(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        CupertinoIcons.plus_circle,
                        color: Theme.of(context).colorScheme.primary,
                        size: 22,
                      ),
                      const SizedBox(width: 14),
                      Text(
                        context.l10n.createNewPlaylist,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Daftar playlist yang ada
              FutureBuilder<List<Playlist>>(
                future: _future,
                builder: (context, snap) {
                  final playlists = snap.data ?? [];
                  if (playlists.isEmpty &&
                      snap.connectionState == ConnectionState.done) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        context.l10n.noPlaylistsYet,
                        style: TextStyle(color: c.secondaryLabel),
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: playlists.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      thickness: 0.5,
                      color: c.separator,
                      indent: 52,
                    ),
                    itemBuilder: (context, i) {
                      final pl = playlists[i];
                      return InkWell(
                        onTap: () => _addToExisting(context, pl),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                CupertinoIcons.music_note,
                                color: Theme.of(context).colorScheme.primary,
                                size: 22,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      pl.name,
                                      style: TextStyle(
                                        color: c.primaryLabel,
                                        fontSize: 15,
                                      ),
                                    ),
                                    Text(
                                      context.l10n.songCount(pl.songIds.length),
                                      style: TextStyle(
                                        color: c.secondaryLabel,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addToExisting(BuildContext context, Playlist pl) async {
    final c = AppColors.of(context);
    final addedMessage = context.l10n.addedToPlaylist(pl.name);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    await PlaylistService.addSong(pl.id, widget.song.id);
    if (!mounted) return;
    navigator.pop(); // tutup sheet playlist
    navigator.pop(); // tutup sheet utama
    messenger.showSnackBar(
      SnackBar(
        content: Text(addedMessage),
        backgroundColor: c.surface2,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _createNew(BuildContext context) async {
    final c = AppColors.of(context);
    final l10n = context.l10n;
    final nameController = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final result = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (dialogCtx) {
        final dc = AppColors.of(dialogCtx);
        return AlertDialog(
          backgroundColor: dc.surface,
          title: Text(
            context.l10n.newPlaylistDialogTitle,
            style: TextStyle(color: dc.primaryLabel, fontSize: 17),
          ),
          content: TextField(
            controller: nameController,
            autofocus: true,
            style: TextStyle(color: dc.primaryLabel),
            decoration: InputDecoration(
              hintText: context.l10n.playlistNameHint,
              hintStyle: TextStyle(color: dc.secondaryLabel),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: dc.separator),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(
                  color: Theme.of(dialogCtx).colorScheme.primary,
                ),
              ),
            ),
            onSubmitted: (v) => Navigator.pop(dialogCtx, v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text(
                context.l10n.cancel,
                style: TextStyle(color: dc.secondaryLabel),
              ),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogCtx, nameController.text.trim()),
              child: Text(
                context.l10n.create,
                style: TextStyle(
                  color: Theme.of(dialogCtx).colorScheme.primary,
                ),
              ),
            ),
          ],
        );
      },
    );
    nameController.dispose();
    if (result == null || result.isEmpty) return;
    final pl = await PlaylistService.createPlaylist(result);
    await PlaylistService.addSong(pl.id, widget.song.id);
    if (!mounted) return;
    final addedMessage = l10n.addedToPlaylist(result);
    navigator.pop(); // tutup sheet playlist
    navigator.pop(); // tutup sheet utama
    messenger.showSnackBar(
      SnackBar(
        content: Text(addedMessage),
        backgroundColor: c.surface2,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
