part of '../player_background.dart';

/// Full-screen artwork-derived background for the alternate player style.
///
/// Artwork is decoded at a bounded 124px size. The expensive blur is baked
/// once per song/viewport scale and kept in a small, memory-only LRU cache.
/// This avoids repeatedly applying a full-screen ImageFilter while Now Playing
/// animates. The source artwork and its repository cache are never modified.
class ArtworkBlurPlayerBackground extends StatefulWidget {
  const ArtworkBlurPlayerBackground({
    super.key,
    required this.songId,
    required this.topOffset,
  });

  static const int _targetSizePx = 124;
  static const double _blurSigma = 28;

  final int songId;

  /// Offset that aligns the viewport-sized image to the physical screen origin
  /// while the player panel grows and is clipped from the bottom.
  final double topOffset;

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
      final sigma = (_blurSigma / imageScale).clamp(0.5, _blurSigma).toDouble();
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
  int _providerSongId = -1;
  ArtworkBlurImageLease? _blurLease;
  String? _requestedBlurKey;
  int _artworkRequestId = 0;
  int _blurRequestId = 0;

  @override
  void initState() {
    super.initState();
    final provider = ArtworkRepository.instance.getProviderSync(
      widget.songId,
      targetSizePx: _targetSizePx,
    );
    if (provider != null) {
      _provider = provider;
      _providerSongId = widget.songId;
    }
    unawaited(_loadArtwork(widget.songId));
  }

  @override
  void didUpdateWidget(ArtworkBlurPlayerBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.songId == widget.songId) return;

    // Invalidate work for the previous track, but keep its rendered frame
    // visible until the new artwork and blur are ready. Clearing both here
    // made the background briefly fall back to black on every track change.
    _blurRequestId++;
    _requestedBlurKey = null;

    final provider = ArtworkRepository.instance.getProviderSync(
      widget.songId,
      targetSizePx: _targetSizePx,
    );
    if (provider != null) {
      _provider = provider;
      _providerSongId = widget.songId;
    }
    unawaited(_loadArtwork(widget.songId));
  }

  Future<void> _loadArtwork(int songId) async {
    final requestId = ++_artworkRequestId;
    if (songId <= 0) {
      if (mounted && widget.songId == songId) {
        final previous = _blurLease;
        setState(() {
          _provider = null;
          _providerSongId = songId;
          _blurLease = null;
          _requestedBlurKey = null;
        });
        previous?.release();
      }
      return;
    }

    final provider = await ArtworkRepository.instance.getProvider(
      songId,
      targetSizePx: _targetSizePx,
    );
    if (!mounted || requestId != _artworkRequestId || provider == null) return;
    setState(() {
      _provider = provider;
      _providerSongId = songId;
    });
  }

  void _ensureBlurredArtwork({
    required int songId,
    required ImageProvider provider,
    required double width,
    required double height,
  }) {
    if (width <= 0 || height <= 0 || !width.isFinite || !height.isFinite) {
      return;
    }

    // Do not accidentally cache the previous track's provider under the new
    // track's key while the new artwork is still loading.
    if (songId != widget.songId) return;

    // ImageFilter sigma is expressed in the destination coordinate space.
    // Scale the pre-blur radius to preserve the existing 32px on-screen look
    // after the 384px source is enlarged to fill the player.
    final imageScale = math.max(width / _targetSizePx, height / _targetSizePx);
    final sourceSigma = (_blurSigma / imageScale)
        .clamp(0.5, _blurSigma)
        .toDouble();
    final key = '$songId:${sourceSigma.toStringAsFixed(1)}';

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
    final cachedImage = _blurLease?.image;
    if (provider == null && cachedImage == null) {
      return const PlayerFallbackBackground();
    }

    final viewport = MediaQuery.sizeOf(context);
    if (provider != null) {
      _ensureBlurredArtwork(
        songId: _providerSongId,
        provider: provider,
        width: viewport.width,
        height: viewport.height,
      );
    }

    final Widget artwork = cachedImage != null
        ? RawImage(
            image: cachedImage,
            width: viewport.width,
            height: viewport.height,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.low,
          )
        : ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: _blurSigma,
              sigmaY: _blurSigma,
            ),
            child: SizedBox(
              width: viewport.width,
              height: viewport.height,
              child: Image(
                image: provider!,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const PlayerFallbackBackground(),
              ),
            ),
          );

    // Draw one viewport-sized background at a stable coordinate origin. The
    // parent's animated panel clips it; drag updates only change this offset and
    // the clip, never the artwork crop or the baked blur radius.
    return RepaintBoundary(
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topCenter,
          minWidth: viewport.width,
          maxWidth: viewport.width,
          minHeight: viewport.height,
          maxHeight: viewport.height,
          child: Transform.translate(
            offset: Offset(0, widget.topOffset),
            child: SizedBox(
              width: viewport.width,
              height: viewport.height,
              child: artwork,
            ),
          ),
        ),
      ),
    );
  }
}
