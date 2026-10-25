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
    if (savedStyle != null &&
        savedStyle >= 0 &&
        savedStyle < NavBarStyle.values.length) {
      navBarStyle.value = NavBarStyle.values[savedStyle];
      // The saved NavBar choice remains authoritative across section collapse.
      glassTheme.value =
          savedGlassTheme || navBarStyle.value != NavBarStyle.solid;
    } else {
      // Keep legacy installations compatible; fresh installs use the default
      // navbar style instead of silently enabling Glass.
      navBarStyle.value = (prefs.getBool('glass_navbar') ?? false)
          ? NavBarStyle.glass
          : NavBarStyle.solid;
      glassTheme.value = savedGlassTheme;
    }

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
    await _save('navbar_style', value.index);
    await _save('glass_theme', glassTheme.value);
  }

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
