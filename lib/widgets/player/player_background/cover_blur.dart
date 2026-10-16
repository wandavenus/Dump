part of '../player_background.dart';

/// Full-screen artwork-derived background for the alternate player style.
///
/// Artwork is decoded at a bounded 384px size. The expensive blur is baked
/// once per song/viewport scale and kept in a small, memory-only LRU cache.
/// This avoids repeatedly applying a full-screen ImageFilter while Now Playing
/// animates. The source artwork and its repository cache are never modified.
class ArtworkBlurPlayerBackground extends StatefulWidget {
  const ArtworkBlurPlayerBackground({super.key, required this.songId});

  static const int _targetSizePx = 384;
  static const double _blurSigma = 32;

  final int songId;

  /// Prepare this song's blurred frame while the player is still collapsed,
  /// so opening Now Playing can use the cached image from its first frame.
  static Future<void> prewarm({
    required int songId,
    required double width,
    required double height,
  }) async {
    if (songId <= 0 ||
        width <= 0 ||
        height <= 0 ||
        !width.isFinite ||
        !height.isFinite) {
      return;
    }

    try {
      final provider = await ArtworkRepository.instance.getProvider(
        songId,
        targetSizePx: _targetSizePx,
      );
      if (provider == null) return;

      final imageScale = math.max(
        width / _targetSizePx,
        height / _targetSizePx,
      );
      final sigma = (_blurSigma / imageScale)
          .clamp(0.5, _blurSigma)
          .toDouble();
      final key = '$songId:${sigma.toStringAsFixed(1)}';
      final lease = await ArtworkBlurCache.acquire(
        key: key,
        provider: provider,
        sigma: sigma,
      );
      lease?.release();
    } on Exception catch (_) {
      // The player keeps the runtime-blur fallback if prewarming fails.
      return;
    }
  }

  @override
  State<ArtworkBlurPlayerBackground> createState() =>
      _ArtworkBlurPlayerBackgroundState();
}

class _ArtworkBlurPlayerBackgroundState
    extends State<ArtworkBlurPlayerBackground> {
  static const int _targetSizePx = ArtworkBlurPlayerBackground._targetSizePx;
  static const double _blurSigma = ArtworkBlurPlayerBackground._blurSigma;

  ImageProvider? _provider;
  ArtworkBlurImageLease? _blurLease;
  String? _requestedBlurKey;
  int _artworkRequestId = 0;
  int _blurRequestId = 0;

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

    // Ignore any in-flight blur for the previous track and release its cache
    // lease. The old cover must never flash over the new song.
    _blurRequestId++;
    _requestedBlurKey = null;
    _blurLease?.release();
    _blurLease = null;

    _provider = ArtworkRepository.instance.getProviderSync(
      widget.songId,
      targetSizePx: _targetSizePx,
    );
    unawaited(_loadArtwork(widget.songId));
  }

  Future<void> _loadArtwork(int songId) async {
    final requestId = ++_artworkRequestId;
    if (songId <= 0) {
      if (mounted) setState(() => _provider = null);
      return;
    }

    final provider = await ArtworkRepository.instance.getProvider(
      songId,
      targetSizePx: _targetSizePx,
    );
    if (!mounted || requestId != _artworkRequestId) return;
    setState(() => _provider = provider);
  }

  void _ensureBlurredArtwork({
    required ImageProvider provider,
    required double width,
    required double height,
  }) {
    if (width <= 0 || height <= 0 || !width.isFinite || !height.isFinite) {
      return;
    }

    // ImageFilter sigma is expressed in the destination coordinate space.
    // Scale the pre-blur radius to preserve the existing 32px on-screen look
    // after the 384px source is enlarged to fill the player.
    final imageScale = math.max(
      width / _targetSizePx,
      height / _targetSizePx,
    );
    final sourceSigma = (_blurSigma / imageScale)
        .clamp(0.5, _blurSigma)
        .toDouble();
    final key = '${widget.songId}:${sourceSigma.toStringAsFixed(1)}';

    if (_requestedBlurKey == key) return;
    _requestedBlurKey = key;
    final requestId = ++_blurRequestId;

    unawaited(
      _loadBlurredArtwork(
        key: key,
        provider: provider,
        sigma: sourceSigma,
        requestId: requestId,
      ),
    );
  }

  Future<void> _loadBlurredArtwork({
    required String key,
    required ImageProvider provider,
    required double sigma,
    required int requestId,
  }) async {
    final lease = await ArtworkBlurCache.acquire(
      key: key,
      provider: provider,
      sigma: sigma,
    );

    if (!mounted || requestId != _blurRequestId) {
      lease?.release();
      return;
    }

    if (lease == null) return;
    final previous = _blurLease;
    setState(() => _blurLease = lease);
    previous?.release();
  }

  @override
  void dispose() {
    _artworkRequestId++;
    _blurRequestId++;
    _blurLease?.release();
    _blurLease = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = _provider;
    if (provider == null) return const PlayerFallbackBackground();

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = MediaQuery.sizeOf(context);
        _ensureBlurredArtwork(
          provider: provider,
          width: viewport.width,
          height: viewport.height,
        );

        // Keep the image at its final full-screen scale while the player panel
        // grows. The parent still clips it to the animated panel bounds, so the
        // cached blur radius and artwork framing do not change on every drag tick.
        final viewportScale = math.max(
          viewport.width / _targetSizePx,
          viewport.height / _targetSizePx,
        );
        final panelScale = math.max(
          constraints.maxWidth / _targetSizePx,
          constraints.maxHeight / _targetSizePx,
        );
        final paintScale = panelScale > 0
            ? (viewportScale / panelScale).clamp(1.0, 8.0).toDouble()
            : 1.0;
        final fallbackSigma = (_blurSigma / paintScale)
            .clamp(0.5, _blurSigma)
            .toDouble();
        final cachedImage = _blurLease?.image;

        final Widget artwork = Transform.scale(
          scale: paintScale,
          alignment: Alignment.center,
          child: cachedImage != null
              ? RawImage(
                  image: cachedImage,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.low,
                )
              : ImageFiltered(
                  // Immediate fallback while the pre-blurred frame is being
                  // built. The outer scale keeps its apparent sigma consistent.
                  imageFilter: ui.ImageFilter.blur(
                    sigmaX: fallbackSigma,
                    sigmaY: fallbackSigma,
                  ),
                  child: SizedBox.expand(
                    child: Image(
                      image: provider,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.low,
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) =>
                          const PlayerFallbackBackground(),
                    ),
                  ),
                ),
        );

        return RepaintBoundary(
          child: ClipRect(
            child: SizedBox.expand(child: artwork),
          ),
        );
      },
    );
  }
}

