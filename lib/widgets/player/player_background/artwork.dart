part of '../player_background.dart';

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
  late final AnimationController _fadeController;
  late final NoiseMotion _motion;
  
  BlurredPair? _currentBlurred;
  BlurredPair? _nextBlurred;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 40),
    )..repeat();
    _fadeController = AnimationController(
     vsync: this,
     duration: const Duration(milliseconds: 450),
   ); 
    _motion = NoiseMotion(
      flowField: FlowField(seed: _seedForSong(widget.songId)),
    );
    _loadBlurred();
  }

  @override
  void didUpdateWidget(covariant BlurredArtworkBackground old) {
    super.didUpdateWidget(old);
    if (old.songId != widget.songId) {
      _loadBlurred();
    }
  }

  Future<void> _loadBlurred() async {
  final requestSongId = widget.songId;

  if (_currentBlurred != null &&
      BlurredImageCache.getSync(requestSongId) == _currentBlurred) {
    return;
  }

  BlurredPair? blurred = BlurredImageCache.getSync(requestSongId);

  blurred ??= await BlurredImageCache.get(
    requestSongId,
    widget.artwork,
  );

  if (!mounted ||
      requestSongId != widget.songId ||
      blurred == null) {
    return;
  }

  // pertama kali
  if (_currentBlurred == null) {
    setState(() {
      _currentBlurred = blurred;
    });
    return;
  }

  setState(() {
    _nextBlurred = blurred;
  });

  await Future<void>.delayed(Duration.zero);

  if (!mounted || requestSongId != widget.songId) return;

  await _fadeController.forward();

  if (!mounted || requestSongId != widget.songId) return;

  setState(() {
    _currentBlurred = _nextBlurred;
    _nextBlurred = null;
  });

  _fadeController.value = 0;
}

  @override
  void dispose() {
    _controller.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = _currentBlurred;
    final next = _nextBlurred;

    // While the blur is computing show a low-opacity raw image so there is
    // no blank flash. Cost is a single decode — no runtime filter.
    if (current == null) {
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

    // Once cached: two cheap texture blits with procedural transform motion.
    // No ImageFilter / BackdropFilter anywhere in this subtree.
    return Stack(
  fit: StackFit.expand,
  children: [
    _buildBlurredPair(current),

    if (next != null)
      FadeTransition(
        opacity: _fadeController,
        child: _buildBlurredPair(next),
      ),

    const ColoredBox(
      color: Color.fromARGB(30, 0, 0, 0),
    ),
  ],
);
  }

  static int _seedForSong(int songId) => songId == 0 ? 1337 : songId;

  Widget _buildBlurredPair(BlurredPair pair) {
  return Stack(
    fit: StackFit.expand,
    children: [
      RepaintBoundary(
        child: _FlowFieldRawImageLayer(
          controller: _controller,
          motion: _motion,
          layer: NoiseMotionLayer.deepBackground,
          image: pair.back,
        ),
      ),
      RepaintBoundary(
        child: _FlowFieldRawImageLayer(
          controller: _controller,
          motion: _motion,
          layer: NoiseMotionLayer.foregroundFog,
          image: pair.front,
        ),
      ),
    ],
  );
  }

}

class _FlowFieldRawImageLayer extends StatelessWidget {
  const _FlowFieldRawImageLayer({
    required this.controller,
    required this.motion,
    required this.layer,
    required this.image,
  });

  final AnimationController controller;
  final NoiseMotion motion;
  final NoiseMotionLayer layer;
  final ui.Image image;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: RawImage(
        image: image,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.low,
      ),
      builder: (_, child) {
        final frame = motion.frameFor(
          layer: layer,
          timeSeconds:
              (controller.lastElapsedDuration?.inMicroseconds ?? 0) / 1000000.0,
        );

        return Opacity(
          opacity: frame.opacity,
          child: Transform.translate(
            offset: frame.translation,
            child: Transform.rotate(
              angle: frame.rotation,
              child: Transform.scale(scale: frame.scale, child: child),
            ),
          ),
        );
      },
    );
  }
}
