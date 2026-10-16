part of '../player_background.dart';

/// Full-screen, artwork-derived background for the alternate player style.
///
/// The source artwork is decoded at a bounded 384px size because the strong
/// blur intentionally removes fine detail. The filtered subtree is isolated
/// from the controls so playback UI rebuilds do not repaint the blur.
class ArtworkBlurPlayerBackground extends StatefulWidget {
  const ArtworkBlurPlayerBackground({super.key, required this.songId});

  final int songId;

  @override
  State<ArtworkBlurPlayerBackground> createState() =>
      _ArtworkBlurPlayerBackgroundState();
}

class _ArtworkBlurPlayerBackgroundState
    extends State<ArtworkBlurPlayerBackground> {
  static const int _targetSizePx = 384;
  static const double _blurSigma = 28;

  ImageProvider? _provider;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _provider = ArtworkRepository.instance.getProviderSync(
      widget.songId,
      targetSizePx: _targetSizePx,
    );
    unawaited(_loadArtwork(widget.songId));
  }

  @override
  void didUpdateWidget(ArtworkBlurPlayerBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.songId == widget.songId) return;

    _provider = ArtworkRepository.instance.getProviderSync(
      widget.songId,
      targetSizePx: _targetSizePx,
    );
    unawaited(_loadArtwork(widget.songId));
  }

  Future<void> _loadArtwork(int songId) async {
    final requestId = ++_requestId;
    if (songId <= 0) {
      if (mounted) setState(() => _provider = null);
      return;
    }

    final provider = await ArtworkRepository.instance.getProvider(
      songId,
      targetSizePx: _targetSizePx,
    );
    if (!mounted || requestId != _requestId) return;
    setState(() => _provider = provider);
  }

  @override
  Widget build(BuildContext context) {
    final provider = _provider;
    if (provider == null) return const PlayerFallbackBackground();

    return RepaintBoundary(
      child: ClipRect(
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(
            sigmaX: _blurSigma,
            sigmaY: _blurSigma,
          ),
          child: SizedBox.expand(
            child: Image(
              image: provider,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.low,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const PlayerFallbackBackground(),
            ),
          ),
        ),
      ),
    );
  }
}
