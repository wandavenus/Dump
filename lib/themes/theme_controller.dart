import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mengontrol tema visual secara global dan per-komponen.
class ThemeController {
  ThemeController._();

  // ─── Master toggle ──────────────────────────────────────────────────────────
  static final ValueNotifier<bool> glassTheme = ValueNotifier(false);

  // ─── Per-komponen glass (hanya aktif jika master ON) ────────────────────────
  // Player UI
  static final ValueNotifier<bool> glassNavBar = ValueNotifier(true);
  static final ValueNotifier<bool> glassAppBar = ValueNotifier(true);
  static final ValueNotifier<bool> glassMiniPlayer = ValueNotifier(true);
  static final ValueNotifier<bool> glassPlayerSheet = ValueNotifier(true);
  // Library & Cards
  static final ValueNotifier<bool> glassAlbumCard = ValueNotifier(true);
  static final ValueNotifier<bool> glassArtistCard = ValueNotifier(true);
  static final ValueNotifier<bool> glassLibraryBar = ValueNotifier(true);
  // Search
  static final ValueNotifier<bool> glassSearchBar = ValueNotifier(true);
  // Settings
  static final ValueNotifier<bool> glassSettings = ValueNotifier(false);

  // ─── Init ───────────────────────────────────────────────────────────────────
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    glassTheme.value = prefs.getBool('glass_theme') ?? false;
    glassNavBar.value = prefs.getBool('glass_navbar') ?? true;
    glassAppBar.value = prefs.getBool('glass_appbar') ?? true;
    glassMiniPlayer.value = prefs.getBool('glass_mini_player') ?? true;
    glassPlayerSheet.value = prefs.getBool('glass_player_sheet') ?? true;
    glassAlbumCard.value = prefs.getBool('glass_album_card') ?? true;
    glassArtistCard.value = prefs.getBool('glass_artist_card') ?? true;
    glassLibraryBar.value = prefs.getBool('glass_library_bar') ?? true;
    glassSearchBar.value = prefs.getBool('glass_search_bar') ?? true;
    glassSettings.value = prefs.getBool('glass_settings') ?? false;
  }

  // ─── Helper ─────────────────────────────────────────────────────────────────
  static bool isGlass(ValueNotifier<bool> component) =>
      glassTheme.value && component.value;

  // ─── Setters ────────────────────────────────────────────────────────────────
  static Future<void> setGlassTheme(bool v) async {
    glassTheme.value = v;
    await _save('glass_theme', v);
  }

  static Future<void> setGlassNavBar(bool v) async {
    glassNavBar.value = v;
    await _save('glass_navbar', v);
  }

  static Future<void> setGlassAppBar(bool v) async {
    glassAppBar.value = v;
    await _save('glass_appbar', v);
  }

  static Future<void> setGlassMiniPlayer(bool v) async {
    glassMiniPlayer.value = v;
    await _save('glass_mini_player', v);
  }

  static Future<void> setGlassPlayerSheet(bool v) async {
    glassPlayerSheet.value = v;
    await _save('glass_player_sheet', v);
  }

  static Future<void> setGlassAlbumCard(bool v) async {
    glassAlbumCard.value = v;
    await _save('glass_album_card', v);
  }

  static Future<void> setGlassArtistCard(bool v) async {
    glassArtistCard.value = v;
    await _save('glass_artist_card', v);
  }

  static Future<void> setGlassLibraryBar(bool v) async {
    glassLibraryBar.value = v;
    await _save('glass_library_bar', v);
  }

  static Future<void> setGlassSearchBar(bool v) async {
    glassSearchBar.value = v;
    await _save('glass_search_bar', v);
  }

  static Future<void> setGlassSettings(bool v) async {
    glassSettings.value = v;
    await _save('glass_settings', v);
  }

  static Future<void> _save(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }
}
