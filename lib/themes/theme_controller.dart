import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mengontrol tema visual secara global dan per-komponen.
class ThemeController {
  ThemeController._();

  // ─── Master toggle ──────────────────────────────────────────────────────────
  static final ValueNotifier<bool> glassTheme = ValueNotifier(false);

  // ─── Per-komponen glass (hanya aktif jika master ON) ────────────────────────
  static final ValueNotifier<bool> glassNavBar = ValueNotifier(true);
  static final ValueNotifier<bool> glassAppBar = ValueNotifier(true);
  static final ValueNotifier<bool> glassMiniPlayer = ValueNotifier(true);
  static final ValueNotifier<bool> glassPlayerSheet = ValueNotifier(true);

  // ─── Init ───────────────────────────────────────────────────────────────────
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    glassTheme.value = prefs.getBool('glass_theme') ?? false;
    glassNavBar.value = prefs.getBool('glass_navbar') ?? true;
    glassAppBar.value = prefs.getBool('glass_appbar') ?? true;
    glassMiniPlayer.value = prefs.getBool('glass_mini_player') ?? true;
    glassPlayerSheet.value = prefs.getBool('glass_player_sheet') ?? true;
  }

  // ─── Helper ─────────────────────────────────────────────────────────────────
  /// Cek apakah sebuah komponen harus tampil glass.
  /// Komponen aktif jika master ON dan toggle komponen ON.
  static bool isGlass(ValueNotifier<bool> component) =>
      glassTheme.value && component.value;

  // ─── Setters ────────────────────────────────────────────────────────────────
  static Future<void> setGlassTheme(bool value) async {
    glassTheme.value = value;
    await _save('glass_theme', value);
  }

  static Future<void> setGlassNavBar(bool value) async {
    glassNavBar.value = value;
    await _save('glass_navbar', value);
  }

  static Future<void> setGlassAppBar(bool value) async {
    glassAppBar.value = value;
    await _save('glass_appbar', value);
  }

  static Future<void> setGlassMiniPlayer(bool value) async {
    glassMiniPlayer.value = value;
    await _save('glass_mini_player', value);
  }

  static Future<void> setGlassPlayerSheet(bool value) async {
    glassPlayerSheet.value = value;
    await _save('glass_player_sheet', value);
  }

  static Future<void> _save(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }
}
