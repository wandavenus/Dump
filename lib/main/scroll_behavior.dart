part of '../main.dart';

class MyScrollBehavior extends MaterialScrollBehavior {
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics();

  // Disable the Android "stretch" overscroll indicator (the rubber-band /
  // spring effect seen when a scroll view hits its edge). Returning the
  // child as-is removes both the stretch and glow indicators entirely.
  @override
  Widget buildOverscrollIndicator(
      BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }
}
