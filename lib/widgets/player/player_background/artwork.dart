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
      duration: const Duration(seconds: 30),
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

          final dx =
              math.sin(t * 3) * 90 +
              math.sin(t * 7) * 18;

          final dy =
              math.sin(t * 2 + math.pi / 2) * 60 +
              math.cos(t * 5) * 12;

          return Transform.translate(
            offset: Offset(dx, dy),
            child: Transform.scale(
              scale:
                  1.75 +
                  math.sin(t * 0.5) * 0.05 +
                  math.cos(t * 2) * 0.01,
              child: child,
            ),
          );
        },
        child: Opacity(
          opacity: 0.18,
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
          final t = _controller.value * math.pi * 2;

          final dx =
              math.sin(t * 5 + math.pi) * 45 +
              math.cos(t * 9) * 10;

          final dy =
              math.sin(t * 4) * 28 +
              math.sin(t * 7 + math.pi / 3) * 8;

          return Transform.translate(
            offset: Offset(dx, dy),
            child: Transform.scale(
              scale:
                  1.42 +
                  math.cos(t * 0.5) * 0.035 +
                  math.sin(t * 3) * 0.008,
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
