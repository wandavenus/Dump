part of '../player_background.dart';

class _AnimatedBlurredPlayerBackgroundState
    extends State<AnimatedBlurredPlayerBackground> {
  Future<Uint8List?>? _artworkFuture;

  @override
  void initState() {
    super.initState();
    _updateArtworkFuture();
  }

  @override
  void didUpdateWidget(AnimatedBlurredPlayerBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.songId != widget.songId) {
      _updateArtworkFuture();
    }
  }

  void _updateArtworkFuture() {
    _artworkFuture = widget.songId > 0
        ? MediaStoreService.getArtwork(widget.songId)
        : Future<Uint8List?>.value();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _artworkFuture,
      builder: (context, snapshot) {
        final artwork = snapshot.data;
        final child = artwork == null || artwork.isEmpty
            ? const PlayerFallbackBackground(key: ValueKey<String>('fallback'))
            : BlurredArtworkBackground(
                songId: widget.songId,
                artwork: artwork,
              );

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 420),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeOutCubic,
          child: child,
        );
      },
    );
  }
}
