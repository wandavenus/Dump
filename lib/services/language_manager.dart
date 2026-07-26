import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Single source of truth for the app's locale/language selection.
///
/// Values stored in SharedPreferences under [_kKey]:
///   "system"  → follow device locale (default)
///   "en"      → force English
///   "id"      → force Bahasa Indonesia
class LanguageManager extends ChangeNotifier {
  static final LanguageManager instance = LanguageManager._();

  static const _kKey = 'app_language';

  LanguageManager._();

  /// null = follow system; otherwise an explicit locale override.
  Locale? _locale;
  Locale? get locale => _locale;

  /// Load saved preference on startup. Call once before runApp().
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kKey) ?? 'system';
    _locale = _fromCode(saved);
  }

  /// Switch to [code]: "system", "en", or "id".
  Future<void> setLanguage(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, code);
    _locale = _fromCode(code);
    notifyListeners();
  }

  /// Saved code string: "system", "en", or "id".
  Future<String> getSavedCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kKey) ?? 'system';
  }

  Locale? _fromCode(String code) => switch (code) {
        'en' => const Locale('en'),
        'id' => const Locale('id'),
        _ => null, // system default
      };
}
