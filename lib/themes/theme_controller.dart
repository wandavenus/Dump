import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Gaya navbar saat Liquid Glass aktif.
enum NavBarStyle {
  /// Navbar solid biasa (tanpa efek glass).
  solid,

  /// Kapsul apung ala iOS 26 (Liquid Glass).
  pill,
}

/// Latar yang dipakai pada full player.
enum PlayerBackgroundStyle {
  /// Latar warna dinamis dari palet artwork (tampilan saat ini).
  fluid,

  /// Artwork lagu yang sedang diputar, diblur memenuhi layar.
  artworkBlur,
}

class ThemeController {
  ThemeController._();

  static SharedPreferences? _prefs;

  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.system);

  static final ValueNotifier<bool> glassTheme = ValueNotifier(false);
  static final ValueNotifier<NavBarStyle> navBarStyle = ValueNotifier(
    NavBarStyle.solid,
  );
  static final ValueNotifier<bool> liquidGlassSectionExpanded =
      ValueNotifier(false);
  static final ValueNotifier<bool> glassMiniPlayer = ValueNotifier(true);
  static final ValueNotifier<PlayerBackgroundStyle> playerBackgroundStyle =
      ValueNotifier(PlayerBackgroundStyle.fluid);

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final prefs = _prefs!;

    mode.value =
        ThemeMode.values[prefs.getInt('theme_mode') ?? ThemeMode.system.index];

    final savedGlassTheme = prefs.getBool('glass_theme') ?? false;
    final savedStyle = prefs.getInt('navbar_style');

    // Stored values remain stable across versions: 0 = Default, 1 = the
    // removed Glass style, 2 = Floating Pill. Removed Glass preferences fall
    // back to Default; preserving 2 keeps existing Floating Pill selections.
    if (savedStyle == 2) {
      navBarStyle.value = NavBarStyle.pill;
      glassTheme.value = true;
    } else {
      navBarStyle.value = NavBarStyle.solid;
      glassTheme.value = savedGlassTheme;
    }
    await _save('navbar_style', _storedNavBarStyle(navBarStyle.value));
    await prefs.remove('glass_navbar');

    liquidGlassSectionExpanded.value =
        prefs.getBool('liquid_glass_section_expanded') ?? false;

    glassMiniPlayer.value = true;
    final savedPlayerBackground = prefs.getInt('player_background_style');
    if (savedPlayerBackground != null &&
        savedPlayerBackground >= 0 &&
        savedPlayerBackground < PlayerBackgroundStyle.values.length) {
      playerBackgroundStyle.value =
          PlayerBackgroundStyle.values[savedPlayerBackground];
    } else {
      playerBackgroundStyle.value = PlayerBackgroundStyle.fluid;
    }
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
    glassTheme.value = value != NavBarStyle.solid;
    await _save('navbar_style', _storedNavBarStyle(value));
    await _save('glass_theme', glassTheme.value);
  }

  static int _storedNavBarStyle(NavBarStyle value) =>
      value == NavBarStyle.pill ? 2 : 0;

  static Future<void> setLiquidGlassSectionExpanded(bool expanded) async {
    liquidGlassSectionExpanded.value = expanded;
    await _save('liquid_glass_section_expanded', expanded);
  }

  static Future<void> setPlayerBackgroundStyle(
    PlayerBackgroundStyle value,
  ) async {
    playerBackgroundStyle.value = value;
    await _save('player_background_style', value.index);
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
