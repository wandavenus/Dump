import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController {
  static final ValueNotifier<bool> glassTheme =
      ValueNotifier(false);

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    glassTheme.value =
        prefs.getBool('glass_theme') ?? true;
  }

  static Future<void> setGlassTheme(
    bool value,
  ) async {
    glassTheme.value = value;

    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(
      'glass_theme',
      value,
    );
  }
}
