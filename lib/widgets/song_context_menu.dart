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

part 'song_context_menu/menu_item.dart';
part 'song_context_menu/info_row.dart';
part 'song_context_menu/add_to_playlist_sheet.dart';

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
        borderRadius: const BorderRadius.vertical(top: Radius.circular(0)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Drag handle ──────────────────────────────────────────────
              const SizedBox(height: 8),
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
            _insetDivider,
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
            _insetDivider,
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
            _insetDivider,
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
            _insetDivider,
            _MenuItem(
              icon: CupertinoIcons.info_circle,
              label: 'Informasi Lagu',
              onTap: () {
                Navigator.pop(context);
                _showSongInfo(context);
              },
            ),

            // ── Grup 5: Hapus ─────────────────────────────────────────────
            _insetDivider,
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
    if (!mounted) return;

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
      builder: (dialogContext) => AlertDialog(
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
            // Pakai context dialog sendiri (bukan context sheet lama yang
            // sudah di-pop di _MenuItem.onTap), kalau tidak tombol ini
            // memanggil Navigator.pop() dengan BuildContext yang sudah
            // deactivated sehingga dialog gagal tertutup.
            onPressed: () => Navigator.pop(dialogContext),
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

// Extracted to part files — see song_context_menu/ directory.
