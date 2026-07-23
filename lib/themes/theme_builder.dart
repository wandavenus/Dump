import 'package:flutter/material.dart';
import 'package:musicplayer/themes/app_themes.dart';

class AppThemeConfig {
  const AppThemeConfig._();

  static ThemeData get light => AppThemes.light;
  static ThemeData get dark => AppThemes.dark;

  static ThemeMode resolve(ThemeMode mode) => mode;
}
