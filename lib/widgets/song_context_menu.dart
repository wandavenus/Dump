import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/local_song.dart';
import '../models/playlist.dart';
import '../pages/album_page.dart';
import '../pages/artist_page.dart';
import '../services/artwork_repository.dart';
import '../services/audio_service.dart';
import '../services/media_store_service.dart';
import '../services/playlist_service.dart';
import '../services/replay_gain_service.dart';
import '../services/song_metadata_service.dart';
import '../utils/zoom_fade_route.dart';
import 'common/swipe_to_dismiss_sheet.dart';
import 'song_artwork.dart';

/// Tampilkan context menu gaya Apple Music untuk sebuah lagu.
void showSongContextMenu(
  BuildContext context, {
  required LocalSong song,
  required List<LocalSong> playlist,
  required int index,
}) {
  final navigator = Navigator.of(context);
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useRootNavigator: true,
    builder: (_) => SongContextMenu(
      song: song,
      playlist: playlist,
      index: index,
      tabNavigator: navigator,
    ),
  );
}

// ─── SongContextMenu ──────────────────────────────────────────────────────────

class SongContextMenu extends StatefulWidget {
  final LocalSong song;
  final List<LocalSong> playlist;
  final int index;
  final NavigatorState tabNavigator;

  const SongContextMenu({
    super.key,
    required this.song,
    required this.playlist,
    required this.index,
    required this.tabNavigator,
  });

  @override
  State<SongContextMenu> createState() => _SongContextMenuState();
}

class _SongContextMenuState extends State<SongContextMenu> {
  bool _isFavorite = false;
  bool _favLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadFavorite();
  }

  Future<void> _loadFavorite() async {
    final fav = await PlaylistService.isFavorite(widget.song.id);
    if (mounted) setState(() { _isFavorite = fav; _favLoaded = true; });
  }

  @override
  Widget build(BuildContext context) {
    return SwipeToDismissSheet(
      child: Material(
        color: const Color(0xFF1C1C1E),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Drag handle ──────────────────────────────────────────────
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

            // ── Song header ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  SongArtwork(
                    songId: widget.song.id,
                    size: 48,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          widget.song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF8E8E93),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Grup 1: Pemutaran ─────────────────────────────────────────
            const Divider(height: 1, thickness: 0.5, color: Color(0xFF48484A)),
            _MenuItem(
              icon: CupertinoIcons.play_fill,
              label: 'Putar Sekarang',
              onTap: () async {
                Navigator.pop(context);
                await AudioService.playSongAt(
                  playlist: widget.playlist,
                  index: widget.index,
                );
              },
            ),
            _insetDivider,
            _MenuItem(
              icon: CupertinoIcons.forward_end_fill,
              label: 'Putar Selanjutnya',
              onTap: () {
                Navigator.pop(context);
                AudioService.addToQueueNext(widget.song);
              },
            ),
            _insetDivider,
            _MenuItem(
              icon: CupertinoIcons.text_badge_plus,
              label: 'Tambah ke Antrian',
              onTap: () {
                Navigator.pop(context);
                AudioService.addToQueue(widget.song);
              },
            ),

            // ── Grup 2: Library ───────────────────────────────────────────
            const Divider(height: 1, thickness: 0.5, color: Color(0xFF48484A)),
            _MenuItem(
              icon: _isFavorite
                  ? CupertinoIcons.heart_fill
                  : CupertinoIcons.heart,
              iconColor: const Color(0xFFF92D48),
              label: _isFavorite ? 'Hapus dari Favorit' : 'Tambah ke Favorit',
              onTap: _favLoaded
                  ? () async {
                      final navigator = Navigator.of(context);
                      final nowFav =
                          await PlaylistService.toggleFavorite(widget.song.id);
                      if (!mounted) return;
                      setState(() => _isFavorite = nowFav);
                      navigator.pop();
                    }
                  : () {},
            ),
            _insetDivider,
            _MenuItem(
              icon: CupertinoIcons.music_note_list,
              label: 'Tambah ke Daftar Putar',
              onTap: () => _showAddToPlaylist(context),
            ),

            // ── Grup 3: Navigasi ──────────────────────────────────────────
            const Divider(height: 1, thickness: 0.5, color: Color(0xFF48484A)),
            _MenuItem(
              icon: CupertinoIcons.music_albums_fill,
              label: 'Buka Album',
              onTap: _openAlbum,
            ),
            _insetDivider,
            _MenuItem(
              icon: CupertinoIcons.person_fill,
              label: 'Buka Artis',
              onTap: _openArtist,
            ),

            // ── Grup 4: Informasi ─────────────────────────────────────────
            const Divider(height: 1, thickness: 0.5, color: Color(0xFF48484A)),
            _MenuItem(
              icon: CupertinoIcons.info_circle,
              label: 'Informasi Lagu',
              onTap: () {
                Navigator.pop(context);
                _showSongInfo(context);
              },
            ),

            // ── Grup 5: Hapus ─────────────────────────────────────────────
            const Divider(height: 1, thickness: 0.5, color: Color(0xFF48484A)),
            _MenuItem(
              icon: CupertinoIcons.trash,
              iconColor: const Color(0xFFF92D48),
              labelColor: const Color(0xFFF92D48),
              label: 'Hapus dari Perangkat',
              onTap: () => _confirmDelete(context),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
  }

  static const _insetDivider = Divider(
    height: 1,
    thickness: 0.5,
    color: Color(0xFF48484A),
    indent: 52,
  );

  // ── Hapus dari Perangkat ───────────────────────────────────────────────────

  Future<void> _confirmDelete(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2E),
        title: const Text(
          'Hapus Lagu?',
          style: TextStyle(color: Colors.white, fontSize: 17),
        ),
        content: Text(
          '"${widget.song.title}" akan dihapus permanen dari perangkat.',
          style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Batal',
              style: TextStyle(color: Color(0xFF0A84FF)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Hapus',
              style: TextStyle(color: Color(0xFFF92D48)),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    navigator.pop();

    final deleted = await MediaStoreService.deleteSong(widget.song.id);
    if (deleted) {
      MediaStoreService.clearSongsCache();
      ArtworkRepository.instance.evict(widget.song.id);
      SongMetadataService.invalidate(widget.song.id);
      unawaited(ReplayGainService.invalidate(widget.song.id));
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Lagu berhasil dihapus'),
          backgroundColor: Color(0xFF2C2C2E),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Gagal menghapus lagu'),
          backgroundColor: Color(0xFF2C2C2E),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ── Tambah ke Daftar Putar ─────────────────────────────────────────────────

  void _showAddToPlaylist(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => _AddToPlaylistSheet(
        song: widget.song,
        tabNavigator: widget.tabNavigator,
      ),
    );
  }

  // ── Buka Album ─────────────────────────────────────────────────────────────

  Future<void> _openAlbum() async {
    final nav = widget.tabNavigator;
    Navigator.pop(context);
    try {
      final allSongs = await MediaStoreService.getSongs();
      final albumSongs =
          allSongs.where((s) => s.album == widget.song.album).toList();
      unawaited(nav.push(
        ZoomFadeRoute<void>(
          settings: RouteSettings(
            arguments: {'album': widget.song, 'songs': albumSongs},
          ),
          page: const AlbumPage(),
        ),
      ));
    } catch (_) {}
  }

  // ── Buka Artis ─────────────────────────────────────────────────────────────

  Future<void> _openArtist() async {
    final nav = widget.tabNavigator;
    Navigator.pop(context);
    try {
      final allSongs = await MediaStoreService.getSongs();
      final artistSongs =
          allSongs.where((s) => s.artist == widget.song.artist).toList();
      unawaited(nav.push(
        ZoomFadeRoute<void>(
          settings: RouteSettings(arguments: artistSongs),
          page: const ArtistPage(),
        ),
      ));
    } catch (_) {}
  }

  // ── Informasi Lagu ─────────────────────────────────────────────────────────

  void _showSongInfo(BuildContext context) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text(
          'Informasi Lagu',
          style: TextStyle(color: Colors.white, fontSize: 17),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoRow(label: 'Judul', value: widget.song.title),
            _InfoRow(label: 'Artis', value: widget.song.artist),
            _InfoRow(label: 'Album', value: widget.song.album),
            _InfoRow(
              label: 'Durasi',
              value: _formatDuration(widget.song.duration),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Tutup',
              style: TextStyle(color: Color(0xFFF92D48)),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
  }
}

// ─── _MenuItem ────────────────────────────────────────────────────────────────

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String label;
  final Color? labelColor;
  final VoidCallback? onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    this.onTap,
    this.iconColor,
    this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Icon(icon, color: iconColor ?? const Color(0xFFF92D48), size: 22),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(color: labelColor ?? Colors.white, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── _InfoRow ─────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── _AddToPlaylistSheet ──────────────────────────────────────────────────────

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
            const Divider(height: 1, thickness: 0.5, color: Color(0xFF48484A)),
            // Buat baru
            InkWell(
              onTap: () => _createNew(context),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                if (playlists.isEmpty && snap.connectionState == ConnectionState.done) {
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
                                crossAxisAlignment: CrossAxisAlignment.start,
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
