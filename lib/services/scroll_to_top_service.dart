import 'package:flutter/foundation.dart';

class ScrollToTopService {
  ScrollToTopService._();

  static final List<ValueNotifier<int>> _signals = List.generate(
    5,
    (_) => ValueNotifier(0),
  );

  static ValueNotifier<int> signal(int tabIndex) => _signals[tabIndex];

  static void trigger(int tabIndex) {
    _signals[tabIndex].value++;
  }
}
