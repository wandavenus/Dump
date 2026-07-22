import 'package:flutter/material.dart';

class AppThemes {
  static const _font = 'SF Pro Text';

  static final ThemeData dark = ThemeData(
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFFF92D48),
      secondary: Color(0xFFF92D48),
      surface: Color(0xFF121212),
    ),
    scaffoldBackgroundColor: Colors.black,
    fontFamily: _font,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
  );

  static final ThemeData light = ThemeData(
    brightness: Brightness.light,
    colorScheme: const ColorScheme.light(
      primary: Color(0xFFF92D48),
      secondary: Color(0xFFF92D48),
      surface: Color(0xFFFFFFFF),
      onSurface: Color(0xFF111111),
    ),
    scaffoldBackgroundColor: Color(0xFFF7F7F7),
    fontFamily: _font,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
  );
}
