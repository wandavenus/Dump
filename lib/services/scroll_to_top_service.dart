import 'package:flutter/foundation.dart';

class ScrollToTopService {
  ScrollToTopService._();

  static final List<ValueNotifier<int>> _signals = List.generate(
    5,
    (_) => ValueNotifier(0),
  );

  // D3 fix: clamp instead of indexing blindly — an out-of-range tab index
  // (today only 0-4 from the bottom nav, but fragile to future callers)
  // would otherwise throw RangeError.
  static int _clampIndex(int tabIndex) => tabIndex.clamp(0, _signals.length - 1);

  static ValueNotifier<int> signal(int tabIndex) => _signals[_clampIndex(tabIndex)];

  static void trigger(int tabIndex) {
    _signals[_clampIndex(tabIndex)].value++;
  }
}
