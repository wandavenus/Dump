/// Guards against Dart's `Unsupported operation: Infinity or NaN toInt`.
///
/// Plain `num.toInt()` / `double.round()` / `.floor()` / `.ceil()` throw that
/// exact message whenever the receiver is `double.nan` or `double.infinity`
/// (`.clamp(lo, hi)` happens to dodge this — `Comparable.compareTo` sorts
/// NaN as greater than everything, so a clamped NaN/Infinity always lands on
/// `hi` — but any bare conversion that skips `clamp()` is exposed).
///
/// The riskiest bare conversions in this app sit on platform-channel/stream
/// boundaries (position/duration ticks from the native player) — a single
/// bad tick must never crash the whole position/duration pipeline. Use
/// [toIntOrElse] there instead of `.toInt()` directly.
library;

extension SafeNumToInt on num {
  /// Converts to `int`, returning [fallback] instead of throwing when this
  /// value is NaN or infinite.
  int toIntOrElse(int fallback) {
    final d = toDouble();
    return d.isFinite ? toInt() : fallback;
  }
}
