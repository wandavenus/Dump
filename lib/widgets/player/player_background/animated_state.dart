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
        _currentSongId = targetSongId;
        _currentArtwork = null;
      });
      return;
    }

    // Ambil data di background tanpa ngerusak UI yang lagi tampil
    MediaStoreService.getArtwork(targetSongId).then((artwork) {
      if (!mounted || widget.songId != targetSongId) return;

      // State diganti barengan pas data udah fix siap (⌐■_■)
      setState(() {
        _currentSongId = targetSongId;
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
