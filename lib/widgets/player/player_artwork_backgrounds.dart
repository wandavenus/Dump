part of 'player_background.dart';

class BlurredArtworkBackground extends StatelessWidget {
  final Uint8List artwork;

  const BlurredArtworkBackground({super.key, required this.artwork});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final cacheWidth =
        (width * MediaQuery.devicePixelRatioOf(context) / 2).round();

    return Stack(
      fit: StackFit.expand,
      children: [
        Transform.scale(
          scale: 1.16,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
            child: Image.memory(
              artwork,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              cacheWidth: cacheWidth,
              filterQuality: FilterQuality.low,
            ),
          ),
        ),
        const ColoredBox(color: Color.fromARGB(130, 0, 0, 0)),
      ],
    );
  }
}

class PlayerFallbackBackground extends StatelessWidget {
  const PlayerFallbackBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF2A2A2E),
            Color(0xFF111113),
            Color(0xFF000000),
          ],
        ),
      ),
    );
  }
}
