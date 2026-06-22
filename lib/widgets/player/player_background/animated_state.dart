part of '../player_background.dart';

class _AnimatedBlurredPlayerBackgroundState
    extends State<AnimatedBlurredPlayerBackground> {
  int? _currentSongId;
  Uint8List? _currentArtwork;

  @override
  void initState() {
    super.initState();
    _loadArtwork();
  }

  @override
  void didUpdateWidget(AnimatedBlurredPlayerBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.songId != widget.songId) {
      _loadArtwork();
    }
  }

  void _loadArtwork() {
    final targetSongId = widget.songId;

    if (targetSongId <= 0) {
      setState(() {
        _currentSongId  = targetSongId;
        _currentArtwork = null;
      });
      return;
    }

    // Use ArtworkRepository so bytes come from the cached WebP file on disk
    // rather than re-extracting from MediaStore on every player open.
    ArtworkRepository.instance.getBytes(targetSongId).then((artwork) {
      if (!mounted || widget.songId != targetSongId) return;
      setState(() {
        _currentSongId  = targetSongId;
        _currentArtwork = artwork;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final showFallback = _currentArtwork == null || _currentArtwork!.isEmpty;

    // Key dan data dijamin selalu sinkron karena pake state yang sama
    final child = showFallback
        ? const PlayerFallbackBackground(key: ValueKey<String>('fallback'))
        : BlurredArtworkBackground(
            key: ValueKey<int>(_currentSongId ?? 0),    
            songId: _currentSongId ?? 0,
            artwork: _currentArtwork!,
          );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      child: child,
    );
  }
}
