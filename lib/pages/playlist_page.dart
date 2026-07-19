import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:musicplayer/models/local_song.dart';
import 'package:musicplayer/models/playlist.dart';
import 'package:musicplayer/services/audio_service.dart';
import 'package:musicplayer/services/history_service.dart';
import 'package:musicplayer/services/media_store_service.dart';
import 'package:musicplayer/services/playlist_service.dart';
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
  final _scroll = ScrollController();
  final _offsetNotifier = ValueNotifier<double>(0.0);

  @override
  void initState() {
    super.initState();
    _load();
    _scroll.addListener(_onScroll);
    MediaStoreService.rescanNotifier.addListener(_onRescan);
  }

  void _onRescan() {
    if (mounted) _load();
  }

  void _onScroll() {
    final o = _scroll.offset;
    if ((o - _offsetNotifier.value).abs() > 0.5) _offsetNotifier.value = o;
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
      final songs =
          ids.where(songMap.containsKey).map((id) => songMap[id]!).toList();

      if (mounted) {
        setState(() {
          _songs = songs;
          _loading = false;
        });
      }
    } catch (_) {
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
        final sorted =
            counts.entries.toList()
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
    final controller = TextEditingController(text: widget.name);
    final result = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1C1C1E),
            title: const Text(
              'Ganti Nama',
              style: TextStyle(color: Colors.white),
            ),
            content: TextField(
              controller: controller,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Nama playlist',
                hintStyle: TextStyle(color: Colors.grey),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Batal'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                child: const Text(
                  'Simpan',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
    );
    controller.dispose();
    if (result != null && result.isNotEmpty && mounted) {
      final playlist = widget.userPlaylist;
      if (playlist == null) return;
      await PlaylistService.renamePlaylist(playlist.id, result);
      if (mounted) setState(() {});
    }
  }

  Future<void> _delete() async {
    if (widget.userPlaylist == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1C1C1E),
            title: const Text(
              'Hapus Playlist?',
              style: TextStyle(color: Colors.white),
            ),
            content: Text(
              'Playlist "${widget.name}" akan dihapus permanen.',
              style: const TextStyle(color: Colors.grey),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Batal'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Hapus', style: TextStyle(color: Color(0xFFF92D48))),
              ),
            ],
          ),
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
    AudioService.playSongAt(playlist: _songs, index: 0);
  }

  void _playSong(int index) {
    AudioService.playSongAt(playlist: _songs, index: index);
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isUserPlaylist = widget.userPlaylist != null;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: FadingTitleAppBar(
        title: widget.name,
        scrollOffsetListenable: _offsetNotifier,
        actions: [
          if (isUserPlaylist) ...[
            IconButton(
              icon: const Icon(
                CupertinoIcons.pencil,
                color: Color(0xFFF92D48),
              ),
              onPressed: _rename,
            ),
            IconButton(
              icon: const Icon(CupertinoIcons.trash, color: Color(0xFFF92D48)),
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
                  : const Divider(
                      height: 1,
                      thickness: 0.5,
                      color: Color(0xFF48484A),
                      indent: 80,
                      endIndent: 16,
                    ),
              itemBuilder: (ctx, i) {
                if (i == 0) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LargePageTitle(title: widget.name),
                      const HeaderDivider(),
                      _PlayAllButton(
                        count: _songs.length,
                        onTap: _playAll,
                      ),
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
                    size: 48,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  title: Text(
                    song.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    song.artist,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: isUserPlaylist
                      ? IconButton(
                          icon: const Icon(
                            Icons.remove_circle_outline,
                            color: Colors.grey,
                            size: 20,
                          ),
                          onPressed: () => _removeSong(song.id),
                        )
                      : Text(
                          _fmt(song.duration),
                          style: const TextStyle(
                            color: Colors.grey,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Text(
            '$count lagu',
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                children: [
                  Icon(Icons.play_arrow, color: Colors.black, size: 18),
                  SizedBox(width: 4),
                  Text(
                    'Putar Semua',
                    style: TextStyle(
                      color: Colors.black,
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
    return const Center(
      child: Text(
        'Belum ada lagu',
        style: TextStyle(color: Colors.grey, fontSize: 16),
      ),
    );
  }
}
