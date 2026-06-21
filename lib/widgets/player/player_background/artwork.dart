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
  ui.Image? _blurredImage;
  int _loadingId = -1;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )..repeat();
    _loadBlurred();
  }

  @override
  void didUpdateWidget(covariant BlurredArtworkBackground old) {
    super.didUpdateWidget(old);
    if (old.songId != widget.songId) {
      _loadingId = widget.songId;
      _loadBlurred();
    }
  }

  Future<void> _loadBlurred() async {
    // Return the cached image immediately if available.
    final cached = BlurredImageCache.getSync(widget.songId);
    if (cached != null) {
      if (mounted) setState(() => _blurredImage = cached);
      return;
    }
    final img = await BlurredImageCache.get(widget.songId, widget.artwork);
    if (mounted) setState(() => _blurredImage = img);
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

    // Once cached: two cheap texture blits with animation transforms.
    // No ImageFilter / BackdropFilter anywhere in this subtree.
    return Stack(
      fit: StackFit.expand,
      children: [
        // Layer 1 — dim, over-scaled, slow oscillation
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (_, child) => Transform.translate(
              offset: Offset(
                math.sin(_controller.value * math.pi * 2) * 18,
                math.cos(_controller.value * math.pi * 2) * 8,
              ),
              child: child,
            ),
            child: Opacity(
              opacity: 0.30,
              child: Transform.scale(
                scale: 1.30,
                child: RawImage(
                  image: blurred,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.low,
                ),
              ),
            ),
          ),
        ),

        // Layer 2 — full opacity, slightly smaller, counter-oscillation
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (_, child) => Transform.translate(
              offset: Offset(
                -math.sin(_controller.value * math.pi * 2) * 10,
                math.cos(_controller.value * math.pi * 2) * 5,
              ),
              child: child,
            ),
            child: Transform.scale(
              scale: 1.16,
              child: RawImage(
                image: blurred,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low,
              ),
            ),
          ),
        ),

        const ColoredBox(color: Color.fromARGB(30, 0, 0, 0)),
      ],
    );
  }
}
