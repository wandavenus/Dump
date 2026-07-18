import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global glass-theme controller — all state is static, no instances.
///
/// ## Design note: all-static pattern
/// [ThemeController] uses a private constructor (`ThemeController._()`) to
/// prevent accidental instantiation while keeping all public members static.
/// This is intentional: the glass theme is a true singleton at the process
/// level and is accessed from multiple unrelated widget subtrees.  A proper
/// InheritedWidget or ChangeNotifier approach would require threading the
/// controller through the entire widget tree — unnecessary complexity for a
/// small, stable set of ten boolean toggles.
///
/// ## Lifecycle
/// Call [init()] once during app startup (after [WidgetsFlutterBinding]).
/// All setters are safe to call from any widget after [init()] completes.
class ThemeController {
  ThemeController._();

  // Cached after init() — avoids a SharedPreferences.getInstance() round-trip
  // on every toggle.  Falls back to a fresh getInstance() if init() was skipped
  // (e.g. tests or web preview).
  static SharedPreferences? _prefs;

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
    _prefs = await SharedPreferences.getInstance();
    final prefs = _prefs!;
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
  static Future<void> setGlassTheme(bool enabled) async {
    glassTheme.value = enabled;
    await _save('glass_theme', enabled);
  }

  static Future<void> setGlassNavBar(bool enabled) async {
    glassNavBar.value = enabled;
    await _save('glass_navbar', enabled);
  }

  static Future<void> setGlassAppBar(bool enabled) async {
    glassAppBar.value = enabled;
    await _save('glass_appbar', enabled);
  }

  static Future<void> setGlassMiniPlayer(bool enabled) async {
    glassMiniPlayer.value = enabled;
    await _save('glass_mini_player', enabled);
  }

  static Future<void> setGlassPlayerSheet(bool enabled) async {
    glassPlayerSheet.value = enabled;
    await _save('glass_player_sheet', enabled);
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

  static Future<void> _save(String key, bool value) async {
    // Re-use the cached instance from init(); fall back to getInstance() in
    // the unlikely case that _save() is called before init() completes.
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }
}
