import '../../log_service.dart';

/// Crossfade controller stub — crossfade is now fully native.
///
/// Dual-player crossfade runs entirely inside `Media3PlaybackService.kt`
/// using a Handler tick.  This Dart class is retained only to satisfy
/// call-sites that haven't been removed yet; all methods are no-ops.
class CrossfadeController {
  CrossfadeController._();

  /// No-op: context is now managed by the native service.
  static void updateContext({
    required bool nextIsGapless,
    required bool loopOne,
  }) {}

  /// Always false — fade state is opaque to Dart.
  static bool get isFading => false;

  /// No-op: crossfade is started by the native position ticker.
  static void initialize() {
    LogService.verbose('Crossfade', 'Native crossfade active (Dart stub)');
  }

  /// No-op.
  static void reset() {}

  /// No-op.
  static void dispose() {}
}
