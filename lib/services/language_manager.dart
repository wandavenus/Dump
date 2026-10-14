import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Single source of truth for the app's locale/language selection.
///
/// Values stored in SharedPreferences under [_kKey]:
///   "system"  → follow device locale
///   "en"      → force English
///   "id"      → force Bahasa Indonesia
class LanguageManager extends ChangeNotifier {
  static final LanguageManager instance = LanguageManager._();

  static const _kKey = 'app_language';

  LanguageManager._();

  bool _useSystem = true;
  Locale? _locale;

  /// Effective locale used by MaterialApp.
  ///
  /// When the saved choice is "system", this is resolved from the current
  /// device locale instead of leaving the resolution to MaterialApp.
  Locale? get locale => _locale;

  /// Load saved preference on startup. Call once before runApp().
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kKey) ?? 'system';
    _applySavedCode(saved, notify: false);
  }

  /// Switch to [code]: "system", "en", or "id".
  Future<void> setLanguage(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, code);
    _applySavedCode(code);
  }

  /// Refresh the effective locale when Android reports a system-locale change.
  ///
  /// Explicit "en"/"id" selections are intentionally left untouched.
  void didChangeSystemLocale(Locale? deviceLocale) {
    if (!_useSystem) return;

    final resolved = _resolveSystemLocale(deviceLocale);
    if (_locale == resolved) return;

    _locale = resolved;
    notifyListeners();
  }

  /// Saved code string: "system", "en", or "id".
  Future<String> getSavedCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kKey) ?? 'system';
  }

  void _applySavedCode(String code, {bool notify = true}) {
    final nextUseSystem = code != 'en' && code != 'id';

    _useSystem = nextUseSystem;
    final nextLocale = nextUseSystem
        ? _resolveSystemLocale(
            WidgetsBinding.instance.platformDispatcher.locale,
          )
        : _fromCode(code);

    final changed = _locale != nextLocale;
    _locale = nextLocale;

    if (notify && (changed || nextUseSystem)) {
      notifyListeners();
    }
  }

  Locale _resolveSystemLocale(Locale? deviceLocale) {
    return switch (deviceLocale?.languageCode) {
      'en' => const Locale('en'),
      'id' => const Locale('id'),
      _ => const Locale('id'),
    };
  }

  Locale? _fromCode(String code) => switch (code) {
    'en' => const Locale('en'),
    'id' => const Locale('id'),
    _ => null,
  };
}
