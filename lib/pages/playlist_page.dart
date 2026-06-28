import 'package:flutter/material.dart';
import 'package:musicplayer/models/local_song.dart';
import 'package:musicplayer/models/playlist.dart';
import 'package:musicplayer/services/audio_service.dart';
import 'package:musicplayer/services/history_service.dart';
import 'package:musicplayer/services/media_store_service.dart';
import 'package:musicplayer/services/playlist_service.dart';
import 'package:musicplayer/widgets/common/scrolling_page_chrome.dart';
import 'package:musicplayer/widgets/song_artwork.dart';

class PlaylistPage extends StatefulWidget {
  final String name;
  final IconData icon;
  final Color iconColor;
  final SmartPlaylistType? smartType;
  final Playlist? userPlaylist;

  const PlaylistPage.smart({
    super.key,
    required this.name,
    required this.icon,
    required this.iconColor,
    required SmartPlaylistType type,
  }) : smartType = type,
       userPlaylist = null;

  PlaylistPage.user({super.key, required Playlist playlist})
    : name = playlist.name,
      icon = Icons.queue_music,
      iconColor = Colors.white,
      smartType = null,
      userPlaylist = playlist;

  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  List<LocalSong> _songs = [];
  bool _loading = true;
  final _scroll = ScrollController();
  double _offset = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    final o = _scroll.offset;
    if ((o - _offset).abs() > 0.5) setState(() => _offset = o);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      List<int> ids;
      if (widget.smartType != null) {
        ids = await _smartIds(widget.smartType!);
      } else {
        ids = List<int>.from(widget.userPlaylist!.songIds);
      }

      final allSongs = await MediaStoreService.getSongs();
      final songMap = {for (final s in allSongs) s.id: s};
      final songs =
          ids.where(songMap.containsKey).map((id) => songMap[id]!).toList();

      if (mounted)
        setState(() {
          _songs = songs;
          _loading = false;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _loading = false;
        });
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
    if (widget.userPlaylist == null) return;
    await PlaylistService.removeSong(widget.userPlaylist!.id, songId);
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
    if (result != null && result.isNotEmpty && mounted) {
      await PlaylistService.renamePlaylist(widget.userPlaylist!.id, result);
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
                child: const Text('Hapus', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
    );
    if (ok == true && mounted) {
      await PlaylistService.deletePlaylist(widget.userPlaylist!.id);
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
        scrollOffset: _offset,
        actions: [
          if (isUserPlaylist) ...[
            IconButton(
              icon: const Icon(
                Icons.drive_file_rename_outline,
                color: Colors.white,
              ),
              onPressed: _rename,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: _delete,
            ),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _songs.isEmpty
          ? _EmptyState(icon: widget.icon, color: widget.iconColor)
          : ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: _songs.length + 1,
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
  final IconData icon;
  final Color color;
  const _EmptyState({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: color.withOpacity(0.4)),
          const SizedBox(height: 16),
          const Text(
            'Belum ada lagu',
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ],
      ),
    );
  }
}
