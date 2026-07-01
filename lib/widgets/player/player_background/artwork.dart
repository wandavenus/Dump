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
  BlurredPair? _blurredImage;
  
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 40),
    )..repeat();
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

  final cached = BlurredImageCache.getSync(
    requestSongId,
  );

  if (cached != null) {
    if (mounted && requestSongId == widget.songId) {
      setState(() => _blurredImage = cached);
    }
    return;
  }

  final img = await BlurredImageCache.get(
    requestSongId,
    widget.artwork,
  );

  if (!mounted) return;

  if (requestSongId != widget.songId) {
    return;
  }

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

    // Once cached: two cheap texture blits with animation transforms.
    // No ImageFilter / BackdropFilter anywhere in this subtree.
    return Stack(
  fit: StackFit.expand,
  children: [
    // Layer 1 — background fog
    RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, child) {
          final t = _controller.value * math.pi * 2;

          return Transform.translate(
            offset: Offset(
              math.sin(t) * 40,
              math.cos(t * 2) * 20,
            ),
            child: Transform.scale(
              scale: 1.50 + math.sin(t) * 0.02,
              child: child,
            ),
          );
        },
        child: Opacity(
          opacity: 0.22,
          child: RawImage(
            image: blurred.back,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.low,
          ),
        ),
      ),
    ),

    // Layer 2 — foreground fog
    RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, child) {
          final t = _controller.value * math.pi * 2 + math.pi;

          return Transform.translate(
            offset: Offset(
              math.cos(t * 2) * 18,
              math.sin(t) * 12,
            ),
            child: Transform.scale(
              scale: 1.25 + math.cos(t) * 0.015,
              child: child,
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

    const ColoredBox(
      color: Color.fromARGB(30, 0, 0, 0),
    ),
  ],
);
  }
}
