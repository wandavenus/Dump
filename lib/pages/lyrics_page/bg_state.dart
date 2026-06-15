part of '../lyrics_page.dart';

Widget build(BuildContext context) {
  return Stack(
    fit: StackFit.expand,
    children: [
      const _LyricsGradient(),

      BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 16,
          sigmaY: 16,
        ),
        child: Container(
          color: Colors.white.withValues(alpha: 0.02),
        ),
      ),
    ],
  );
}