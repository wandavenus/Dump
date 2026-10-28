part of '../player_content.dart';

/// Rebuilds only the [Opacity] wrapper when the player sheet progress changes.
///
/// The [child] is passed through as the [ValueListenableBuilder] child, so the
/// expensive player content it contains is not reconstructed on every tick.
class _SheetProgressOpacity extends StatelessWidget {
  final double Function(double progress) opacityFor;
  final Widget child;

  const _SheetProgressOpacity({required this.opacityFor, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: PlayerSheetController.progress,
      child: child,
      builder: (context, progress, child) =>
          Opacity(opacity: opacityFor(progress), child: child),
    );
  }
}

/// Rebuilds only the progress-dependent cover transforms, shadow, and opacity.
///
/// The decoded artwork subtree is passed as the builder child, keeping the
/// image widget, Hero, and FittedBox stable while the sheet is dragged.
class _SheetProgressArtwork extends StatelessWidget {
  final LocalSong song;
  final double largeCoverSize;
  final double coverLeft;
  final double coverTop;
  final double sectionHeight;
  final bool showOverlay;
  final bool hideArtwork;

  const _SheetProgressArtwork({
    required this.song,
    required this.largeCoverSize,
    required this.coverLeft,
    required this.coverTop,
    required this.sectionHeight,
    required this.showOverlay,
    required this.hideArtwork,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final artwork = FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: largeCoverSize,
        height: largeCoverSize,
        child: Hero(
          tag: PlayerHeroTags.artwork(song),
          child: SongArtwork(
            songId: song.id,
            size: largeCoverSize,
            borderRadius: BorderRadius.zero,
            // Hairline already drawn on the outer Container above — avoids
            // a doubled/mismatched stroke here.
            showBorder: false,
          ),
        ),
      ),
    );

    return ValueListenableBuilder<double>(
      valueListenable: PlayerSheetController.progress,
      child: artwork,
      builder: (context, progress, child) {
        return Opacity(
          opacity: hideArtwork ? 0.0 : 1.0,
          child: Transform.translate(
            offset: Offset(
              showOverlay
                  ? (16.0 - coverLeft)
                  : lerpDouble(22.0 - coverLeft, 0.0, progress)!,
              showOverlay
                  ? (-0.5 - coverTop)
                  : lerpDouble(sectionHeight - 140 - coverTop, 0.0, progress)!,
            ),
            child: Transform.scale(
              scale: showOverlay
                  ? (_smallCoverSize / largeCoverSize)
                  : lerpDouble(70.0 / largeCoverSize, 1.0, progress)!,
              alignment: Alignment.topLeft,
              child: Container(
                width: largeCoverSize,
                height: largeCoverSize,
                clipBehavior: Clip.hardEdge,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: Colors.black,
                  // Hairline stroke on the visible bounding box — must live
                  // here (not inside SongArtwork) since the inner image is
                  // cropped by FittedBox/cover and would clip a border drawn
                  // on its own edge.
                  border: Border.all(
                    color: brightness == Brightness.dark
                        ? kArtworkHairlineDarkColor
                        : kArtworkHairlineLightColor,
                    width: kArtworkHairlineWidth,
                    // Inset alignment — stays crisp as the Transform scales it.
                    strokeAlign: BorderSide.strokeAlignInside,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: 0.0 + (0.10 * progress),
                      ),
                      blurRadius: 0.0 + (1 * progress),
                      spreadRadius: 0.0 + (0.1 * progress),
                      offset: Offset(0, 0 + (1 * progress)),
                    ),
                  ],
                ),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}
