part of '../radio_sections.dart';

// ─── Data for smart playlist cards ───────────────────────────────────────────

class _SmartCardData {
  final String name;
  final IconData icon;
  final Color color;
  final SmartPlaylistType type;
  const _SmartCardData({
    required this.name,
    required this.icon,
    required this.color,
    required this.type,
  });
}

// Non-const because MaterialColor isn't a compile-time constant.
final _smartCards = [
  _SmartCardData(
    name: 'Favorit',
    icon: Icons.favorite,
    color: Colors.red,
    type: SmartPlaylistType.favorites,
  ),
  _SmartCardData(
    name: 'Diputar Terakhir',
    icon: Icons.history,
    color: Colors.blue,
    type: SmartPlaylistType.recentlyPlayed,
  ),
  _SmartCardData(
    name: 'Paling Sering',
    icon: Icons.trending_up,
    color: Colors.orange,
    type: SmartPlaylistType.mostPlayed,
  ),
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

  Future<void> _load() async {
    final data = _smartCards[widget.index];
    try {
      List<int> ids;
      switch (data.type) {
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
      }
    } catch (_) {}
  }

  void _open() {
    final data = _smartCards[widget.index];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlaylistPage.smart(
          name: data.name,
          icon: data.icon,
          iconColor: data.color,
          type: data.type,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PlaylistCard(
      name: _smartCards[widget.index].name,
      subtitle: _count == 0 ? 'Belum ada lagu' : '$_count lagu',
      emptyIcon: _smartCards[widget.index].icon,
      emptyIconColor: _smartCards[widget.index].color,
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
  }

  void _open() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlaylistPage.user(playlist: widget.playlist),
      ),
    ).then((_) {
      // refresh after returning (songs may have been removed)
      widget.onDeleted();
    });
  }

  void _onLongPress() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade700,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text(
                'Hapus Playlist',
                style: TextStyle(color: Colors.red),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.playlist.songIds.length;
    return PlaylistCard(
      name: widget.playlist.name,
      subtitle: count == 0 ? 'Belum ada lagu' : '$count lagu',
      emptyIcon: Icons.queue_music,
      emptyIconColor: Colors.white,
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
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text(
          'Playlist Baru',
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
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text(
              'Buat',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await PlaylistService.createPlaylist(name);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: [
              const Text(
                'Playlist Saya',
                style: TextStyle(
                  color: Colors.white,
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
                    color: const Color(0xFF2C2C2E),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.add, color: Colors.white, size: 16),
                      SizedBox(width: 4),
                      Text(
                        'Buat',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_playlists.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'Belum ada playlist',
                style: TextStyle(color: Colors.grey, fontSize: 14),
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
