part of '../player_background.dart';

class _AnimatedBlurredPlayerBackgroundState
    extends State<AnimatedBlurredPlayerBackground> {
  Future<Uint8List?>? _artworkFuture;

  Widget? _previousLayer;
  Widget? _currentLayer;

  @override
  void initState() {
    super.initState();
    _updateArtworkFuture();
  }

  @override
  void didUpdateWidget(
    AnimatedBlurredPlayerBackground oldWidget,
  ) {
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
      key: ValueKey<int>(widget.songId),
      future: _artworkFuture,
      builder: (context, snapshot) {
        final artwork = snapshot.data;

        final newLayer =
            artwork == null || artwork.isEmpty
                ? const PlayerFallbackBackground(
                    key: ValueKey<String>('fallback'),
                  )
                : BlurredArtworkBackground(
                    key: ValueKey<int>(widget.songId),
                    songId: widget.songId,
                    artwork: artwork,
                  );

        if (_currentLayer == null) {
          _currentLayer = newLayer;
        } else if (_currentLayer!.key != newLayer.key) {
          _previousLayer = _currentLayer;
          _currentLayer = newLayer;
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            if (_previousLayer != null)
              Positioned.fill(
                child: AnimatedOpacity(
                  opacity: 0,
                  duration: const Duration(
                    milliseconds: 900,
                  ),
                  curve: Curves.easeInOutQuart,
                  onEnd: () {
                    if (mounted) {
                      setState(() {
                        _previousLayer = null;
                      });
                    }
                  },
                  child: _previousLayer!,
                ),
              ),

            if (_currentLayer != null)
              Positioned.fill(
                child: AnimatedOpacity(
                  opacity: 1,
                  duration: const Duration(
                    milliseconds: 700,
                  ),
                  curve: Curves.easeInOutQuart,
                  child: _currentLayer!,
                ),
              ),
          ],
        );
      },
    );
  }
}
