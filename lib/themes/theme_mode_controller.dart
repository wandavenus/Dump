import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeModeController {
  ThemeModeController._();

  static SharedPreferences? _prefs;

  static final ValueNotifier<ThemeModeOption> mode =
      ValueNotifier(ThemeModeOption.system);

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    mode.value = ThemeModeOption.values[
      _prefs!.getInt('theme_mode') ?? ThemeModeOption.system.index,
    ];
  }

  static Future<void> setMode(ThemeModeOption value) async {
    mode.value = value;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setInt('theme_mode', value.index);
  }
}

enum ThemeModeOption {
  system,
  light,
  dark,
}
