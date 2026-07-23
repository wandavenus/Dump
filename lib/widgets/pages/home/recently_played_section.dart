part of '../home_sections.dart';

class _RecentlyPlayedSection extends StatefulWidget {
  const _RecentlyPlayedSection();

  @override
  State<_RecentlyPlayedSection> createState() => _RecentlyPlayedSectionState();
}

class _RecentlyPlayedSectionState extends State<_RecentlyPlayedSection> {
  List<LocalSong> _songs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Synchronous first-frame init: if both the song cache and the recently-
    // played ID cache are ready (populated by warmUp calls in main()), build
    // the list immediately so the first build() renders content, not a spinner.
    final cachedSongs = MediaStoreService.cachedSongs;
    final cachedIds   = HistoryService.cachedRecentIds;
    if (cachedSongs != null && cachedIds != null) {
      _songs = _buildRecent(cachedSongs, cachedIds);
      _isLoading = false;
    }
    _load();
    MediaStoreService.rescanNotifier.addListener(_onRescan);
  }

  void _onRescan() {
    if (mounted) _load();
  }

  @override
  void dispose() {
    MediaStoreService.rescanNotifier.removeListener(_onRescan);
    super.dispose();
  }

  List<LocalSong> _buildRecent(List<LocalSong> allSongs, List<int> recentIds) {
    final songMap = {for (final s in allSongs) s.id: s};
    return recentIds
        .where(songMap.containsKey)
        .map((id) => songMap[id]!)
        .toList();
  }

  Future<void> _load() async {
    try {
      final recentIds = await HistoryService.getRecentlyPlayedIds();
      final allSongs = await MediaStoreService.getSongs();
      final recent = _buildRecent(allSongs, recentIds);
      if (mounted) {
        setState(() { _songs = recent; _isLoading = false; });
        unawaited(
          ArtworkRepository.instance.prefetch(recent.map((s) => s.id).toList()),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() { _isLoading = false; });
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
      return SizedBox(
        height: 250,
        child: Center(
          child: Text(
            'Belum ada lagu yang diputar',
            style: TextStyle(color: AppColors.of(context).secondaryLabel),
          ),
        ),
      );
    }
    return LocalSongCarousel(songs: _songs);
  }
}
