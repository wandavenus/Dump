import 'package:flutter/foundation.dart';

class PlayerSheetController {
  PlayerSheetController._();

  static final ValueNotifier<bool> expanded =
      ValueNotifier<bool>(false);

  static void open() {
    expanded.value = true;
  }

  static void close() {
    expanded.value = false;
  }

  static void toggle() {
    expanded.value = !expanded.value;
  }
}
