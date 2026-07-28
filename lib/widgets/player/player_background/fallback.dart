part of '../player_background.dart';

class PlayerFallbackBackground extends StatelessWidget {
  const PlayerFallbackBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A2A2E), Color(0xFF111113), Color(0xFF000000)],
        ),
      ),
    );
  }
}
