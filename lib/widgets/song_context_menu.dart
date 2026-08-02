import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../extensions/localization_extension.dart';

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
import '../theme/app_colors.dart';
import '../themes/app_theme_extension.dart';
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
  unawaited(
    showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: AnimationStyle.noAnimation,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => SongContextMenu(
        song: song,
        playlist: playlist,
        index: index,
        tabNavigator: navigator,
      ),
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
    unawaited(_loadFavorite());
  }

  Future<void> _loadFavorite() async {
    final fav = await PlaylistService.isFavorite(widget.song.id);
    if (mounted) {
      setState(() {
        _isFavorite = fav;
        _favLoaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return SwipeToDismissSheet(
      child: Material(
        color: c.surface,
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
                  color: c.dragHandle,
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
                            style: TextStyle(
                              color: c.primaryLabel,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            widget.song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: c.secondaryLabel,
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
              _insetDivider(c),
              _MenuItem(
                icon: CupertinoIcons.play_fill,
                label: context.l10n.playNow,
                onTap: () async {
                  Navigator.pop(context);
                  await AudioService.playSongAt(
                    playlist: widget.playlist,
                    index: widget.index,
                  );
                },
              ),
              _insetDivider(c),
              _MenuItem(
                icon: CupertinoIcons.forward_end_fill,
                label: context.l10n.playNext,
                onTap: () {
                  Navigator.pop(context);
                  AudioService.addToQueueNext(widget.song);
                },
              ),
              _insetDivider(c),
              _MenuItem(
                icon: CupertinoIcons.text_badge_plus,
                label: context.l10n.addToQueue,
                onTap: () {
                  Navigator.pop(context);
                  AudioService.addToQueue(widget.song);
                },
              ),

              // ── Grup 2: Library ───────────────────────────────────────────
              _insetDivider(c),
              _MenuItem(
                icon: _isFavorite
                    ? CupertinoIcons.heart_fill
                    : CupertinoIcons.heart,
                iconColor: Theme.of(context).colorScheme.primary,
                label: _isFavorite
                    ? context.l10n.removeFromFavorites
                    : context.l10n.addToFavorites,
                onTap: _favLoaded
                    ? () async {
                        final navigator = Navigator.of(context);
                        final nowFav = await PlaylistService.toggleFavorite(
                          widget.song.id,
                        );
                        if (!mounted) return;
                        setState(() => _isFavorite = nowFav);
                        navigator.pop();
                      }
                    : () {},
              ),
              _insetDivider(c),
              _MenuItem(
                icon: CupertinoIcons.music_note_list,
                label: context.l10n.addToPlaylistMenu,
                onTap: () => _showAddToPlaylist(context),
              ),

              // ── Grup 3: Navigasi ──────────────────────────────────────────
              _insetDivider(c),
              _MenuItem(
                icon: CupertinoIcons.music_albums_fill,
                label: context.l10n.openAlbum,
                onTap: _openAlbum,
              ),
              _insetDivider(c),
              _MenuItem(
                icon: CupertinoIcons.person_fill,
                label: context.l10n.openArtist,
                onTap: _openArtist,
              ),

              // ── Grup 4: Informasi ─────────────────────────────────────────
              _insetDivider(c),
              _MenuItem(
                icon: CupertinoIcons.info_circle,
                label: context.l10n.songInformation,
                onTap: () {
                  Navigator.pop(context);
                  _showSongInfo(context);
                },
              ),

              // ── Grup 5: Hapus ─────────────────────────────────────────────
              _insetDivider(c),
              _MenuItem(
                icon: CupertinoIcons.trash,
                iconColor: Theme.of(context).colorScheme.primary,
                labelColor: Theme.of(context).colorScheme.primary,
                label: context.l10n.deleteFromDevice,
                onTap: () => _confirmDelete(context),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _insetDivider(AppThemeExtension c) =>
      Divider(height: 1, thickness: 0.5, color: c.separator, indent: 52);

  // ── Hapus dari Perangkat ───────────────────────────────────────────────────

  Future<void> _confirmDelete(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    if (!mounted) return;

    navigator.pop();

    final c = AppColors.of(context);
    final l = context.l10n;
    final deleted = await MediaStoreService.deleteSong(widget.song.id);
    if (deleted) {
      MediaStoreService.clearSongsCache();
      ArtworkRepository.instance.evict(widget.song.id);
      SongMetadataService.invalidate(widget.song.id);
      unawaited(ReplayGainService.invalidate(widget.song.id));
      messenger.showSnackBar(
        SnackBar(
          content: Text(l.songDeletedMsg),
          backgroundColor: c.surface2,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l.songDeleteFailedMsg),
          backgroundColor: c.surface2,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ── Tambah ke Daftar Putar ─────────────────────────────────────────────────

  void _showAddToPlaylist(BuildContext context) {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        sheetAnimationStyle: AnimationStyle.noAnimation,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        useRootNavigator: true,
        builder: (_) => _AddToPlaylistSheet(
          song: widget.song,
          tabNavigator: widget.tabNavigator,
        ),
      ),
    );
  }

  // ── Buka Album ─────────────────────────────────────────────────────────────

  Future<void> _openAlbum() async {
    final nav = widget.tabNavigator;
    Navigator.pop(context);
    try {
      final allSongs = await MediaStoreService.getSongs();
      final albumSongs = allSongs
          .where((s) => s.album == widget.song.album)
          .toList();
      unawaited(
        nav.push(
          ZoomFadeRoute<void>(
            settings: RouteSettings(
              arguments: {'album': widget.song, 'songs': albumSongs},
            ),
            page: const AlbumPage(),
          ),
        ),
      );
    } on Exception catch (_) {}
  }

  // ── Buka Artis ─────────────────────────────────────────────────────────────

  Future<void> _openArtist() async {
    final nav = widget.tabNavigator;
    Navigator.pop(context);
    try {
      final allSongs = await MediaStoreService.getSongs();
      final artistSongs = allSongs
          .where((s) => s.artist == widget.song.artist)
          .toList();
      unawaited(
        nav.push(
          ZoomFadeRoute<void>(
            settings: RouteSettings(arguments: artistSongs),
            page: const ArtistPage(),
          ),
        ),
      );
    } on Exception catch (_) {}
  }

  // ── Informasi Lagu ─────────────────────────────────────────────────────────

  void _showSongInfo(BuildContext context) {
    final c = AppColors.of(context);
    final l = context.l10n;
    unawaited(
      showDialog<void>(
        context: context,
        useRootNavigator: true,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: c.surface,
          title: Text(
            l.songInformation,
            style: TextStyle(color: c.primaryLabel, fontSize: 17),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoRow(label: l.fieldTitle, value: widget.song.title),
              _InfoRow(label: l.fieldArtist, value: widget.song.artist),
              _InfoRow(label: l.fieldAlbum, value: widget.song.album),
              _InfoRow(
                label: l.fieldDuration,
                value: _formatDuration(widget.song.duration),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                l.close,
                style: TextStyle(
                  color: Theme.of(dialogContext).colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
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
