import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Gaya navbar saat Liquid Glass aktif.
enum NavBarStyle {
  /// Navbar solid biasa (tanpa efek glass).
  solid,

  /// Strip glass selebar layar (tampilan lama).
  glass,

  /// Kapsul apung ala iOS 26 (Liquid Glass).
  pill,
}

class ThemeController {
  ThemeController._();

  static SharedPreferences? _prefs;

  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.system);

  static final ValueNotifier<bool> glassTheme = ValueNotifier(false);
  static final ValueNotifier<NavBarStyle> navBarStyle = ValueNotifier(
    NavBarStyle.glass,
  );
  static final ValueNotifier<bool> glassAppBar = ValueNotifier(true);
  static final ValueNotifier<bool> glassMiniPlayer = ValueNotifier(true);

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final prefs = _prefs!;

    mode.value =
        ThemeMode.values[prefs.getInt('theme_mode') ?? ThemeMode.system.index];

    glassTheme.value = prefs.getBool('glass_theme') ?? false;
    final savedStyle = prefs.getInt('navbar_style');
    if (savedStyle != null &&
        savedStyle >= 0 &&
        savedStyle < NavBarStyle.values.length) {
      navBarStyle.value = NavBarStyle.values[savedStyle];
    } else {
      // Migrasi dari toggle lama (glass_navbar).
      navBarStyle.value = (prefs.getBool('glass_navbar') ?? true)
          ? NavBarStyle.glass
          : NavBarStyle.solid;
    }
    glassAppBar.value = prefs.getBool('glass_appbar') ?? true;
    glassMiniPlayer.value = prefs.getBool('glass_mini_player') ?? true;
  }

  static Future<void> setMode(ThemeMode value) async {
    mode.value = value;
    await _save('theme_mode', value.index);
  }

  static Future<void> setGlassTheme(bool enabled) async {
    glassTheme.value = enabled;
    await _save('glass_theme', enabled);
  }

  static Future<void> setNavBarStyle(NavBarStyle value) async {
    navBarStyle.value = value;
    await _save('navbar_style', value.index);
  }

  static Future<void> setGlassAppBar(bool enabled) async {
    glassAppBar.value = enabled;
    await _save('glass_appbar', enabled);
  }

  static Future<void> setGlassMiniPlayer(bool enabled) async {
    glassMiniPlayer.value = enabled;
    await _save('glass_mini_player', enabled);
  }

  static Future<void> _save(String key, Object value) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    }
  }
}
