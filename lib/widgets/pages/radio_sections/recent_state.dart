part of '../radio_sections.dart';

class _RecentlyPlayedSectionState extends State<_RecentlyPlayedSection> {
  List<LocalSong> _songs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    MediaStoreService.rescanNotifier.addListener(_onRescan);
  }

  void _onRescan() {
    if (mounted) unawaited(_load());
  }

  @override
  void dispose() {
    MediaStoreService.rescanNotifier.removeListener(_onRescan);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final recentIds = await HistoryService.getRecentlyPlayedIds();
      final allSongs = await MediaStoreService.getSongs();
      final songMap = {for (final s in allSongs) s.id: s};
      final recent = recentIds
          .where(songMap.containsKey)
          .map((id) => songMap[id]!)
          .toList();
      if (mounted) {
        setState(() {
          _songs = recent;
          _isLoading = false;
        });
      }
    } on Exception catch (_) {
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
      return SizedBox(
        height: 250,
        child: Center(
          child: Text(
            context.l10n.noRecentlyPlayed,
            style: TextStyle(color: AppColors.of(context).secondaryLabel),
          ),
        ),
      );
    }
    return LocalSongCarousel(songs: _songs);
  }
}
