part of '../song_context_menu.dart';

// ─── _AddToPlaylistSheet ──────────────────────────────────────────────────────
//
// Bottom sheet for selecting an existing playlist or creating a new one.
// Opened from [_SongContextMenuState._showAddToPlaylist].

class _AddToPlaylistSheet extends StatefulWidget {
  final LocalSong song;
  final NavigatorState tabNavigator;
  const _AddToPlaylistSheet({
    required this.song,
    required this.tabNavigator,
  });

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
    return SwipeToDismissSheet(
      child: Material(
        color: const Color(0xFF1C1C1E),
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
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Tambah ke Daftar Putar',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Divider(
                  height: 1,
                  thickness: 0.5,
                  color: Color(0xFF48484A),
                  indent: 52),
              // Buat baru
              InkWell(
                onTap: () => _createNew(context),
                child: const Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Icon(
                        CupertinoIcons.plus_circle,
                        color: Color(0xFFF92D48),
                        size: 22,
                      ),
                      SizedBox(width: 14),
                      Text(
                        'Buat Daftar Putar Baru',
                        style: TextStyle(
                          color: Color(0xFFF92D48),
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
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Belum ada daftar putar',
                        style: TextStyle(color: Color(0xFF8E8E93)),
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: playlists.length,
                    separatorBuilder: (_, _) => const Divider(
                      height: 1,
                      thickness: 0.5,
                      color: Color(0xFF48484A),
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
                              const Icon(
                                CupertinoIcons.music_note,
                                color: Color(0xFFF92D48),
                                size: 22,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      pl.name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                      ),
                                    ),
                                    Text(
                                      '${pl.songIds.length} lagu',
                                      style: const TextStyle(
                                        color: Color(0xFF8E8E93),
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
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    await PlaylistService.addSong(pl.id, widget.song.id);
    if (!mounted) return;
    navigator.pop(); // tutup sheet playlist
    navigator.pop(); // tutup sheet utama
    messenger.showSnackBar(
      SnackBar(
        content: Text('Ditambahkan ke ${pl.name}'),
        backgroundColor: const Color(0xFF2C2C2E),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _createNew(BuildContext context) async {
    final nameController = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final result = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text(
          'Daftar Putar Baru',
          style: TextStyle(color: Colors.white, fontSize: 17),
        ),
        content: TextField(
          controller: nameController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Nama Daftar Putar',
            hintStyle: TextStyle(color: Color(0xFF8E8E93)),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF48484A)),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFF92D48)),
            ),
          ),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Batal',
              style: TextStyle(color: Color(0xFF8E8E93)),
            ),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, nameController.text.trim()),
            child: const Text(
              'Buat',
              style: TextStyle(color: Color(0xFFF92D48)),
            ),
          ),
        ],
      ),
    );
    nameController.dispose();
    if (result == null || result.isEmpty) return;
    final pl = await PlaylistService.createPlaylist(result);
    await PlaylistService.addSong(pl.id, widget.song.id);
    if (!mounted) return;
    navigator.pop(); // tutup sheet playlist
    navigator.pop(); // tutup sheet utama
    messenger.showSnackBar(
      SnackBar(
        content: Text('Ditambahkan ke $result'),
        backgroundColor: const Color(0xFF2C2C2E),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
