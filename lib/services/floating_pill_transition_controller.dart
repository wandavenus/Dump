import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'player_sheet_controller.dart';

/// Drives the collapsed navigation/player dock directly from vertical scrolling.
///
/// ScrollPosition listeners update the shared progress before layout, avoiding
/// the one-frame lag that can occur when using ScrollNotification for geometry.
class FloatingPillTransitionController {
  FloatingPillTransitionController._();

  /// Scrolling this distance fully docks the mini-player into the navbar.
  static const double compactScrollDistance = 72.0;
  static const Duration _resetDuration = Duration(milliseconds: 220);

  static final ValueNotifier<double> progress = ValueNotifier<double>(0.0);
  static final Expando<double> _lastKnownPixels =
      Expando<double>('floatingPillLastKnownPixels');

  static bool _dockEnabled = false;
  static bool _miniPlayerVisible = false;
  static ScrollPosition? _observedPosition;
  static double? _observedPixels;
  static Ticker? _resetTicker;

  /// Enables scroll-driven geometry only while the floating pill style is active.
  static void setDockEnabled(bool enabled) {
    if (_dockEnabled == enabled) return;
    _dockEnabled = enabled;
    if (!enabled) {
      _detachObservedPosition();
      _resetTicker?.dispose();
      _resetTicker = null;
      progress.value = 0.0;
    }
  }

  /// Keeps an empty dock from appearing when there is no mini-player to dock.
  ///
  /// When playback ends, the navbar restores its full capsule with a short
  /// vsync-driven settle rather than snapping its geometry to the start.
  static void setMiniPlayerVisible(bool visible) {
    if (_miniPlayerVisible == visible) return;
    _miniPlayerVisible = visible;

    _resetTicker?.dispose();
    _resetTicker = null;

    if (!visible) {
      _detachObservedPosition();
      if (_dockEnabled) {
        _animateProgressToZero();
      } else {
        progress.value = 0.0;
      }
    }
  }

  static void _animateProgressToZero() {
    final start = progress.value;
    if (start <= 0.001) {
      progress.value = 0.0;
      return;
    }

    _resetTicker = Ticker((elapsed) {
      final rawT = (elapsed.inMilliseconds / _resetDuration.inMilliseconds)
          .clamp(0.0, 1.0)
          .toDouble();
      final easedT = Curves.easeOutCubic.transform(rawT);
      progress.value = start * (1.0 - easedT);

      if (rawT >= 1.0) {
        progress.value = 0.0;
        _resetTicker?.dispose();
        _resetTicker = null;
      }
    });
    unawaited(_resetTicker!.start());
  }

  /// Root listener for the tab navigator tree.
  ///
  /// Notifications select the active ScrollPosition, while its Listenable drives
  /// geometry synchronously before layout. Returning false preserves any
  /// page-level scroll observers and app-bar effects.
  static bool handleScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;

    if (!_dockEnabled ||
        !_miniPlayerVisible ||
        PlayerSheetController.progress.value > 0.015) {
      _detachObservedPosition();
      return false;
    }
    if (notification.metrics.axis != Axis.vertical) return false;

    final position = _positionFrom(notification);

    if (notification is ScrollStartNotification) {
      if (position != null) _attachObservedPosition(position);
      return false;
    }

    if (notification is ScrollEndNotification) {
      _detachObservedPosition(position);
      return false;
    }

    if (notification is ScrollUpdateNotification) {
      if (position != null) {
        // Its listener has already accounted for this pixel change.
        if (identical(position, _observedPosition)) return false;

        // Handles a Scrollable that did not produce a start notification for
        // this observer (e.g. a restored or programmatically adjusted position).
        _attachObservedPosition(
          position,
          fallbackDelta: notification.scrollDelta,
        );
      } else if (_observedPosition == null) {
        final delta = notification.scrollDelta;
        if (delta != null) {
          _applyAxisDelta(delta, notification.metrics.axisDirection);
        }
      }
      return false;
    }

    if (notification is OverscrollNotification) {
      // Overscroll is the unapplied remainder; it does not duplicate the
      // ScrollPosition listener's applied pixel delta.
      _applyAxisDelta(
        notification.overscroll,
        notification.metrics.axisDirection,
      );
    }

    return false;
  }

  static ScrollPosition? _positionFrom(ScrollNotification notification) {
    final context = notification.context;
    if (context == null) return null;

    // ScrollNotification.context is inside the originating Scrollable.
    // Ancestor lookup avoids registering an inherited dependency in an event.
    return context.findAncestorStateOfType<ScrollableState>()?.position;
  }

  static void _attachObservedPosition(
    ScrollPosition position, {
    double? fallbackDelta,
  }) {
    if (identical(position, _observedPosition)) return;

    _detachObservedPosition();

    final currentPixels = position.pixels;
    final previousPixels = _lastKnownPixels[position];
    _observedPosition = position;
    _observedPixels = currentPixels;
    _lastKnownPixels[position] = currentPixels;
    position.addListener(_onObservedPositionChanged);

    if (previousPixels != null) {
      _applyAxisDelta(
        currentPixels - previousPixels,
        position.axisDirection,
      );
    } else if (fallbackDelta != null) {
      _applyAxisDelta(fallbackDelta, position.axisDirection);
    }
  }

  static void _onObservedPositionChanged() {
    final position = _observedPosition;
    if (position == null) return;

    final previousPixels = _observedPixels;
    final currentPixels = position.pixels;
    _observedPixels = currentPixels;
    _lastKnownPixels[position] = currentPixels;

    if (previousPixels != null) {
      _applyAxisDelta(
        currentPixels - previousPixels,
        position.axisDirection,
      );
    }
  }

  static void _detachObservedPosition([ScrollPosition? expected]) {
    final position = _observedPosition;
    if (position == null ||
        (expected != null && !identical(position, expected))) {
      return;
    }

    _lastKnownPixels[position] = position.pixels;
    position.removeListener(_onObservedPositionChanged);
    _observedPosition = null;
    _observedPixels = null;
  }

  static void _applyAxisDelta(double delta, AxisDirection direction) {
    updateFromScrollDelta(
      direction == AxisDirection.up ? -delta : delta,
    );
  }

  /// Applies a signed scroll delta to the shared transition progress.
  ///
  /// Positive deltas collapse the dock; negative deltas reverse it.
  @visibleForTesting
  static void updateFromScrollDelta(double delta) {
    if (!delta.isFinite ||
        delta == 0 ||
        !_dockEnabled ||
        !_miniPlayerVisible ||
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
    _detachObservedPosition();
    _resetTicker?.dispose();
    _resetTicker = null;
    progress.value = 0.0;
  }
}
