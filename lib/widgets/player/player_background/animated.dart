part of '../player_background.dart';

class AnimatedBlurredPlayerBackground extends StatefulWidget {
  final int songId;

  const AnimatedBlurredPlayerBackground({super.key, required this.songId});

  @override
  State<AnimatedBlurredPlayerBackground> createState() =>
      _AnimatedBlurredPlayerBackgroundState();
}
