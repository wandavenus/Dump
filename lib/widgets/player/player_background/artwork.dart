part of '../player_background.dart';

class BlurredArtworkBackground extends StatefulWidget {
  final Uint8List artwork;

  const BlurredArtworkBackground({
    super.key,
    required this.artwork,
  });

  @override
  State<BlurredArtworkBackground> createState() =>
      _BlurredArtworkBackgroundState();
}

class _BlurredArtworkBackgroundState
    extends State<BlurredArtworkBackground>
    with SingleTickerProviderStateMixin {

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cacheWidth =
        (width * MediaQuery.of(context).devicePixelRatio / 2).round();

    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedBuilder(
  animation: _controller,
  builder: (_, child) {
    return Transform.translate(
      offset: Offset(
  math.sin(_controller.value * math.pi * 2) * 18,
  math.cos(_controller.value * math.pi * 2) * 8,
),
      child: child,
    );
  },
  child: Transform.scale(
    scale: 1.16,
    child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
            child: Image.memory(
              widget.artwork,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              cacheWidth: cacheWidth,
              filterQuality: FilterQuality.none,
              ),
            ),
          ),
        ),
        const ColoredBox(color: Color.fromARGB(0, 0, 0, 0)),
      ],
    );
  }
}
