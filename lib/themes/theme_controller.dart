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
  static final ValueNotifier<bool> glassAlbumCard = ValueNotifier(true);
  static final ValueNotifier<bool> glassArtistCard = ValueNotifier(true);
  static final ValueNotifier<bool> glassLibraryBar = ValueNotifier(true);
  static final ValueNotifier<bool> glassSearchBar = ValueNotifier(true);
  static final ValueNotifier<bool> glassSettings = ValueNotifier(false);

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
    glassAlbumCard.value = prefs.getBool('glass_album_card') ?? true;
    glassArtistCard.value = prefs.getBool('glass_artist_card') ?? true;
    glassLibraryBar.value = prefs.getBool('glass_library_bar') ?? true;
    glassSearchBar.value = prefs.getBool('glass_search_bar') ?? true;
    glassSettings.value = prefs.getBool('glass_settings') ?? false;
  }

  static Future<void> setMode(ThemeMode value) async {
    mode.value = value;
    await _save('theme_mode', value.index);
  }

  static bool isGlass(ValueNotifier<bool> component) =>
      glassTheme.value && component.value;

  /// Apakah navbar sedang memakai gaya pill (iOS 26) — hanya berlaku saat
  /// Liquid Glass aktif.
  static bool get isPillNavBar =>
      glassTheme.value && navBarStyle.value == NavBarStyle.pill;

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

  static Future<void> setGlassAlbumCard(bool enabled) async {
    glassAlbumCard.value = enabled;
    await _save('glass_album_card', enabled);
  }

  static Future<void> setGlassArtistCard(bool enabled) async {
    glassArtistCard.value = enabled;
    await _save('glass_artist_card', enabled);
  }

  static Future<void> setGlassLibraryBar(bool enabled) async {
    glassLibraryBar.value = enabled;
    await _save('glass_library_bar', enabled);
  }

  static Future<void> setGlassSearchBar(bool enabled) async {
    glassSearchBar.value = enabled;
    await _save('glass_search_bar', enabled);
  }

  static Future<void> setGlassSettings(bool enabled) async {
    glassSettings.value = enabled;
    await _save('glass_settings', enabled);
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
