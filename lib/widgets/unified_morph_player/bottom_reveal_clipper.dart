part of '../unified_morph_player.dart';

// ── Reveal clipper used by the mini-player entry animation ───────────────────
// Clips away everything at/below a given height so the mini player appears to
// rise from behind/inside the bottom nav bar instead of sliding on top of it.
class _BottomRevealClipper extends CustomClipper<Rect> {
  final double visibleHeight;
  const _BottomRevealClipper(this.visibleHeight);

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width, visibleHeight);

  @override
  bool shouldReclip(covariant _BottomRevealClipper oldClipper) =>
      oldClipper.visibleHeight != visibleHeight;
}
