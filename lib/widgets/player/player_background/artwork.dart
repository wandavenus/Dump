part of '../player_background.dart';

/// Animated player background rendered from cached blurred artwork.
class BlurredArtworkBackground extends StatefulWidget {
  final int songId;
  final Uint8List artwork;

  const BlurredArtworkBackground({
    super.key,
    required this.songId,
    required this.artwork,
  });

  @override
  State<BlurredArtworkBackground> createState() =>
      _BlurredArtworkBackgroundState();
}

class _BlurredArtworkBackgroundState extends State<BlurredArtworkBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Stopwatch _motionClock;
  late NoiseMotionSampler _motionSampler;
  BlurredPair? _blurredImage;

  static const NoiseMotionConfig _backgroundMotion = NoiseMotionConfig(
    origin: Offset(0, 0),
    translationExtent: Offset(132, 96),
    rotationExtent: 0.018,
    baseScale: 1.84,
    scaleExtent: 0.045,
    baseOpacity: 0.20,
    opacityExtent: 0.018,
  );

  static const NoiseMotionConfig _foregroundMotion = NoiseMotionConfig(
    origin: Offset(4096, -2048),
    translationExtent: Offset(70, 52),
    rotationExtent: 0.012,
    baseScale: 1.42,
    scaleExtent: 0.028,
    baseOpacity: 1.0,
  );

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )..repeat();
    _motionClock = Stopwatch()..start();
    _motionSampler = NoiseMotionSampler(
      FlowField(config: FlowFieldConfig(seed: widget.songId)),
    );
    _loadBlurred();
  }

  @override
  void didUpdateWidget(covariant BlurredArtworkBackground old) {
    super.didUpdateWidget(old);
    if (old.songId != widget.songId) {
      _motionSampler = NoiseMotionSampler(
        FlowField(config: FlowFieldConfig(seed: widget.songId)),
      );
      _motionClock
        ..reset()
        ..start();
      _loadBlurred();
    }
  }

  Future<void> _loadBlurred() async {
    final requestSongId = widget.songId;

    final cached = BlurredImageCache.getSync(requestSongId);
    if (cached != null) {
      if (mounted && requestSongId == widget.songId) {
        setState(() => _blurredImage = cached);
      }
      return;
    }

    final img = await BlurredImageCache.get(requestSongId, widget.artwork);

    if (!mounted) return;
    if (requestSongId != widget.songId) return;

    setState(() {
      _blurredImage = img;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final blurred = _blurredImage;

    // While the blur is computing show a low-opacity raw image so there is
    // no blank flash.  Cost is a single decode — no runtime filter.
    if (blurred == null) {
      return Opacity(
        opacity: 0.25,
        child: Image.memory(
          widget.artwork,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.low,
        ),
      );
    }

    // Once cached: two cheap texture blits with procedural transforms.
    // The controller only ticks frames; motion samples elapsed wall-clock time so
    // repeat() never creates a visible reset or positional jump.
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (_, child) {
              final motion = _motionSampler.sample(
                _backgroundMotion,
                _motionClock.elapsedMicroseconds /
                    Duration.microsecondsPerSecond,
              );

              return Opacity(
                opacity: motion.opacity,
                child: Transform.translate(
                  offset: motion.translation,
                  child: Transform.rotate(
                    angle: motion.rotation,
                    child: Transform.scale(scale: motion.scale, child: child),
                  ),
                ),
              );
            },
            child: RawImage(
              image: blurred.back,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.low,
            ),
          ),
        ),
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (_, child) {
              final motion = _motionSampler.sample(
                _foregroundMotion,
                _motionClock.elapsedMicroseconds /
                    Duration.microsecondsPerSecond,
              );

              return Transform.translate(
                offset: motion.translation,
                child: Transform.rotate(
                  angle: motion.rotation,
                  child: Transform.scale(scale: motion.scale, child: child),
                ),
              );
            },
            child: RawImage(
              image: blurred.front,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.low,
            ),
          ),
        ),
        const ColoredBox(color: Color.fromARGB(30, 0, 0, 0)),
      ],
    );
  }
}
