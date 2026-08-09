import 'dart:async' show unawaited;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:musicplayer/extensions/localization_extension.dart';
import 'package:musicplayer/models/local_song.dart';
import 'package:musicplayer/models/playlist.dart';
import 'package:musicplayer/services/audio_service.dart';
import 'package:musicplayer/services/history_service.dart';
import 'package:musicplayer/services/media_store_service.dart';
import 'package:musicplayer/services/playlist_service.dart';
import 'package:musicplayer/theme/app_colors.dart';
import 'package:musicplayer/widgets/common/scrolling_page_chrome.dart';
import 'package:musicplayer/widgets/common_actions.dart';
import 'package:musicplayer/widgets/song_artwork.dart';

class PlaylistPage extends StatefulWidget {
  final String name;
  final SmartPlaylistType? smartType;
  final Playlist? userPlaylist;

  const PlaylistPage.smart({
    super.key,
    required this.name,
    required SmartPlaylistType type,
  }) : smartType = type,
       userPlaylist = null;

  PlaylistPage.user({super.key, required Playlist playlist})
    : name = playlist.name,
      smartType = null,
      userPlaylist = playlist;

  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  List<LocalSong> _songs = [];
  bool _loading = true;
  late String _playlistName;
  final _scroll = ScrollController();
  final _offsetNotifier = ValueNotifier<double>(0.0);

  @override
  void initState() {
    super.initState();
    _playlistName = widget.name;
    unawaited(_load());
    _scroll.addListener(_onScroll);
    MediaStoreService.rescanNotifier.addListener(_onRescan);
  }

  @override
  void didUpdateWidget(covariant PlaylistPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.name != widget.name) {
      _playlistName = widget.name;
    }
  }

  void _onRescan() {
    if (mounted) unawaited(_load());
  }

  static const double _kAnimEnd = 140.0;

  void _onScroll() {
    final clamped = _scroll.offset.clamp(0.0, _kAnimEnd);
    if (clamped != _offsetNotifier.value) _offsetNotifier.value = clamped;
  }

  @override
  void dispose() {
    MediaStoreService.rescanNotifier.removeListener(_onRescan);
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _offsetNotifier.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      List<int> ids;
      final smartType = widget.smartType;
      if (smartType != null) {
        ids = await _smartIds(smartType);
      } else {
        final playlist = widget.userPlaylist;
        ids = playlist != null ? List<int>.from(playlist.songIds) : [];
      }

      final allSongs = await MediaStoreService.getSongs();
      final songMap = {for (final s in allSongs) s.id: s};
      final songs = ids
          .where(songMap.containsKey)
          .map((id) => songMap[id]!)
          .toList();

      if (mounted) {
        setState(() {
          _songs = songs;
          _loading = false;
        });
      }
    } on Exception catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<List<int>> _smartIds(SmartPlaylistType type) async {
    switch (type) {
      case SmartPlaylistType.favorites:
        return PlaylistService.getFavoriteIds();
      case SmartPlaylistType.recentlyPlayed:
        return HistoryService.getRecentlyPlayedIds();
      case SmartPlaylistType.mostPlayed:
        final counts = await HistoryService.getPlayCounts();
        final sorted = counts.entries.toList()
          ..sort((a, b) => (b.value as int).compareTo(a.value as int));
        return sorted
            .map((e) => int.tryParse(e.key) ?? 0)
            .where((id) => id != 0)
            .toList();
    }
  }

  Future<void> _removeSong(int songId) async {
    final playlist = widget.userPlaylist;
    if (playlist == null) return;
    await PlaylistService.removeSong(playlist.id, songId);
    if (mounted) setState(() => _songs.removeWhere((s) => s.id == songId));
  }

  Future<void> _rename() async {
    if (widget.userPlaylist == null) return;
    final c = AppColors.of(context);
    final l = context.l10n;
    final controller = TextEditingController(text: _playlistName);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final dc = AppColors.of(ctx);
        return AlertDialog(
          backgroundColor: dc.surface,
          title: Text(
            l.renamePlaylist,
            style: TextStyle(color: dc.primaryLabel),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: TextStyle(color: dc.primaryLabel),
            decoration: InputDecoration(
              hintText: l.playlistNameHint,
              hintStyle: TextStyle(color: dc.secondaryLabel),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: dc.separator),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: dc.primaryLabel),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: Text(l.save, style: TextStyle(color: c.primaryLabel)),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (result != null && result.isNotEmpty && mounted) {
      final playlist = widget.userPlaylist;
      if (playlist == null) return;
      await PlaylistService.renamePlaylist(playlist.id, result);
      if (mounted) setState(() => _playlistName = result);
    }
  }

  Future<void> _delete() async {
    if (widget.userPlaylist == null) return;
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final dc = AppColors.of(ctx);
        return AlertDialog(
          backgroundColor: dc.surface,
          title: Text(
            l.deletePlaylistConfirm,
            style: TextStyle(color: dc.primaryLabel),
          ),
          content: Text(
            l.deletePlaylistBody(_playlistName),
            style: TextStyle(color: dc.secondaryLabel),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                l.delete,
                style: TextStyle(color: Theme.of(ctx).colorScheme.primary),
              ),
            ),
          ],
        );
      },
    );
    if ((ok ?? false) && mounted) {
      final playlist = widget.userPlaylist;
      if (playlist == null) return;
      await PlaylistService.deletePlaylist(playlist.id);
      if (mounted) Navigator.pop(context);
    }
  }

  void _playAll() {
    if (_songs.isEmpty) return;
    unawaited(AudioService.playSongAt(playlist: _songs, index: 0));
  }

  void _playSong(int index) {
    unawaited(AudioService.playSongAt(playlist: _songs, index: index));
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isUserPlaylist = widget.userPlaylist != null;
    final c = AppColors.of(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: FadingTitleAppBar(
        title: _playlistName,
        scrollOffsetListenable: _offsetNotifier,
        leading: CupertinoButton(
          padding: const EdgeInsets.only(left: 8),
          onPressed: () => Navigator.of(context).pop(),
          child: Icon(
            CupertinoIcons.arrow_left,
            color: Theme.of(context).colorScheme.primary,
            size: 28,
          ),
        ),
        actions: [
          if (isUserPlaylist) ...[
            IconButton(
              icon: Icon(
                CupertinoIcons.create_solid,
                color: Theme.of(context).colorScheme.primary,
              ),
              onPressed: _rename,
            ),
            IconButton(
              icon: Icon(
                CupertinoIcons.trash,
                color: Theme.of(context).colorScheme.primary,
              ),
              onPressed: _delete,
            ),
          ],
          const CommonActions(),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _songs.isEmpty
          ? const _EmptyState()
          : ListView.separated(
              controller: _scroll,
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: _songs.length + 1,
              separatorBuilder: (ctx, i) => i == 0
                  ? const SizedBox.shrink()
                  : Divider(
                      height: 1,
                      thickness: 0.5,
                      color: c.separator,
                      indent: 80,
                      endIndent: 16,
                    ),
              itemBuilder: (ctx, i) {
                if (i == 0) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LargePageTitle(title: _playlistName),
                      const HeaderDivider(),
                      _PlayAllButton(count: _songs.length, onTap: _playAll),
                    ],
                  );
                }
                final song = _songs[i - 1];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 2,
                  ),
                  leading: SongArtwork(
                    songId: song.id,
                    size: 55,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  title: Text(
                    song.title,
                    style: TextStyle(color: c.primaryLabel, fontSize: 15),
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    song.artist,
                    style: TextStyle(color: c.secondaryLabel, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: isUserPlaylist
                      ? IconButton(
                          icon: Icon(
                            Icons.remove_circle_outline,
                            color: c.secondaryLabel,
                            size: 20,
                          ),
                          onPressed: () => _removeSong(song.id),
                        )
                      : Text(
                          _fmt(song.duration),
                          style: TextStyle(
                            color: c.secondaryLabel,
                            fontSize: 12,
                          ),
                        ),
                  onTap: () => _playSong(i - 1),
                );
              },
            ),
    );
  }
}

class _PlayAllButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _PlayAllButton({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Text(
            context.l10n.songCount(count),
            style: TextStyle(color: c.secondaryLabel, fontSize: 14),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    context.l10n.playAll,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        context.l10n.noSongsInList,
        style: TextStyle(
          color: AppColors.of(context).secondaryLabel,
          fontSize: 16,
        ),
      ),
    );
  }
}
