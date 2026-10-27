import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'player_sheet_controller.dart';

/// Drives the collapsed navigation/player dock directly from vertical scrolling.
///
/// Progress is shared by the floating navbar and mini-player so their geometry
/// follows the same scroll delta instead of running independent animations.
class FloatingPillTransitionController {
  FloatingPillTransitionController._();

  /// Scrolling this distance fully docks the mini-player into the navbar.
  static const double compactScrollDistance = 72.0;

  static final ValueNotifier<double> progress = ValueNotifier<double>(0.0);

  /// Receives notifications from the tab navigator tree.
  ///
  /// Returning false keeps notifications available to page-level app-bar
  /// animations and other scroll observers.
  static bool handleScrollNotification(ScrollNotification notification) {
    if (PlayerSheetController.progress.value > 0.015) return false;

    double? delta;
    if (notification is ScrollUpdateNotification &&
        notification.metrics.axis == Axis.vertical) {
      delta = notification.scrollDelta;
    } else if (notification is OverscrollNotification &&
        notification.metrics.axis == Axis.vertical) {
      delta = notification.overscroll;
    }

    if (delta == null || !delta.isFinite) return false;

    // Normalize reversed vertical scrollables so scrolling into content always
    // collapses the dock and returning toward the start expands it.
    if (notification.metrics.axisDirection == AxisDirection.up) {
      delta = -delta;
    }
    updateFromScrollDelta(delta);
    return false;
  }

  /// Applies a signed vertical scroll delta to the shared transition progress.
  ///
  /// Positive deltas collapse the dock; negative deltas reverse it. This method
  /// is intentionally frame-synchronous for direct-manipulation motion.
  static void updateFromScrollDelta(double delta) {
    if (!delta.isFinite ||
        delta == 0 ||
        PlayerSheetController.progress.value > 0.015) {
      return;
    }

    final current = progress.value;
    final next = (current + delta / compactScrollDistance)
        .clamp(0.0, 1.0)
        .toDouble();
    if ((next - current).abs() >= 0.001) {
      progress.value = next;
    }
  }

  @visibleForTesting
  static void reset() {
    progress.value = 0.0;
  }
}
