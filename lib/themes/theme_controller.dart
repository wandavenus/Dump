import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mengontrol tema aplikasi termasuk sistem Liquid Glass per-komponen.
class ThemeController {
  ThemeController._();

  // ─── Master switch ───────────────────────────────────────────────────────
  static final ValueNotifier<bool> glassTheme = ValueNotifier(false);

  // ─── Per-komponen (hanya aktif bila master ON) ────────────────────────────
  static final ValueNotifier<bool> glassNavBar = ValueNotifier(true);
  static final ValueNotifier<bool> glassAppBar = ValueNotifier(true);
  static final ValueNotifier<bool> glassMiniPlayer = ValueNotifier(true);
  static final ValueNotifier<bool> glassCards = ValueNotifier(false);

  /// Composite listenable — rebuild ketika state glass mana pun berubah.
  static Listenable get allGlass => Listenable.merge([
        glassTheme,
        glassNavBar,
        glassAppBar,
        glassMiniPlayer,
        glassCards,
      ]);

  // ─── Convenience getters ─────────────────────────────────────────────────
  static bool get isNavBarGlass => glassTheme.value && glassNavBar.value;
  static bool get isAppBarGlass => glassTheme.value && glassAppBar.value;
  static bool get isMiniPlayerGlass => glassTheme.value && glassMiniPlayer.value;
  static bool get isCardsGlass => glassTheme.value && glassCards.value;

  // ─── Init ────────────────────────────────────────────────────────────────
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    glassTheme.value = prefs.getBool('glass_theme') ?? false;
    glassNavBar.value = prefs.getBool('glass_nav_bar') ?? true;
    glassAppBar.value = prefs.getBool('glass_app_bar') ?? true;
    glassMiniPlayer.value = prefs.getBool('glass_mini_player') ?? true;
    glassCards.value = prefs.getBool('glass_cards') ?? false;
  }

  // ─── Master setter ────────────────────────────────────────────────────────
  static Future<void> setGlassTheme(bool value) async {
    glassTheme.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('glass_theme', value);
  }

  // ─── Per-komponen setter ──────────────────────────────────────────────────
  static Future<void> setGlassNavBar(bool value) =>
      _setComponent('glass_nav_bar', glassNavBar, value);
  static Future<void> setGlassAppBar(bool value) =>
      _setComponent('glass_app_bar', glassAppBar, value);
  static Future<void> setGlassMiniPlayer(bool value) =>
      _setComponent('glass_mini_player', glassMiniPlayer, value);
  static Future<void> setGlassCards(bool value) =>
      _setComponent('glass_cards', glassCards, value);

  static Future<void> _setComponent(
      String key, ValueNotifier<bool> notifier, bool value) async {
    notifier.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }
}
