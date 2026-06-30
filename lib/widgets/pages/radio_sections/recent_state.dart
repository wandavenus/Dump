part of '../radio_sections.dart';

class _RecentlyPlayedSectionState extends State<_RecentlyPlayedSection> {
  List<LocalSong> _songs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final recentIds = await HistoryService.getRecentlyPlayedIds();
      final allSongs = await MediaStoreService.getSongs();
      final songMap = {for (final s in allSongs) s.id: s};
      final recent =
          recentIds
              .where(songMap.containsKey)
              .map((id) => songMap[id]!)
              .toList();
      if (mounted) {
        setState(() {
          _songs = recent;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 250,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_songs.isEmpty) {
      return const SizedBox(
        height: 250,
        child: Center(
          child: Text(
            'No recently played songs',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    return LocalSongCarousel(songs: _songs);
  }
}
