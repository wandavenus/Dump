import 'package:flutter/material.dart';
import 'package:musicplayer/themes/app_theme_extension.dart';

class AppThemes {
  static const _font = 'SF Pro Text';

  static const _textStyle = TextStyle(fontFamily: _font);

  static ThemeData _base({required Brightness brightness}) {
    final isDark = brightness == Brightness.dark;

    return ThemeData(
      brightness: brightness,
      colorScheme: isDark
          ? const ColorScheme.dark(
              primary: Color(0xFFF92D48),
              secondary: Color(0xFFF92D48),
              surface: Color(0xFF121212),
            )
          : const ColorScheme.light(
              primary: Color(0xFFF92D48),
              secondary: Color(0xFFF92D48),
              surface: Color(0xFFFFFFFF),
              onSurface: Color(0xFF111111),
            ),
      scaffoldBackgroundColor:
          isDark ? Colors.black : const Color(0xFFF7F7F7),
      fontFamily: _font,
      textTheme: const TextTheme(
        displayLarge: _textStyle,
        displayMedium: _textStyle,
        displaySmall: _textStyle,
        headlineLarge: _textStyle,
        headlineMedium: _textStyle,
        headlineSmall: _textStyle,
        titleLarge: _textStyle,
        titleMedium: _textStyle,
        titleSmall: _textStyle,
        bodyLarge: _textStyle,
        bodyMedium: _textStyle,
        bodySmall: _textStyle,
        labelLarge: _textStyle,
        labelMedium: _textStyle,
        labelSmall: _textStyle,
      ),
      dialogTheme: const DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(3)),
        ),
      ),
      popupMenuTheme: const PopupMenuThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(3)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        contentTextStyle: TextStyle(
          color: isDark ? Colors.white : Colors.black,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      extensions: [
        AppThemeExtension(
          glassColor: Colors.white,
          glassOpacity: isDark ? 0.08 : 0.55,
          artworkOverlay: isDark
              ? const Color(0x99000000)
              : const Color(0x99FFFFFF),
        ),
      ],
    );
  }

  static final ThemeData dark = _base(brightness: Brightness.dark);
  static final ThemeData light = _base(brightness: Brightness.light);
}
