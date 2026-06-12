import 'package:flutter/foundation.dart';

class PlayerSheetController {
  PlayerSheetController._();

  static final ValueNotifier<bool> expanded =
      ValueNotifier<bool>(false);

  static final ValueNotifier<double> progress =
      ValueNotifier<double>(0.0);

  static void open() {
    expanded.value = true;
    progress.value = 1.0;
  }

  static void close() {
    expanded.value = false;
    progress.value = 0.0;
  }

  static void toggle() {
    if (expanded.value) {
      close();
    } else {
      open();
    }
  }
}
