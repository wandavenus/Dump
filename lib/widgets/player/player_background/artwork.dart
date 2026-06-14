part of '../player_background.dart';

class BlurredArtworkBackground extends StatelessWidget {
  final Uint8List artwork;

  const BlurredArtworkBackground({super.key, required this.artwork});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cacheWidth =
        (width * MediaQuery.of(context).devicePixelRatio / 2).round();

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
