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
      scaffoldBackgroundColor: isDark ? Colors.black : const Color(0xFFF7F7F7),
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
        backgroundColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
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
          // ── Original glass ─────────────────────────────────────────────────
          glassColor: Colors.white,
          glassOpacity: isDark ? 0.08 : 0.55,
          artworkOverlay: isDark
              ? const Color(0x99000000)
              : const Color(0x99FFFFFF),

          // ── Surface hierarchy ──────────────────────────────────────────────
          surface: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          surface2: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFEBEBF0),
          surface3: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFD1D1D6),
          codeBackground: isDark
              ? const Color(0xFF0A0A0A)
              : const Color(0xFFE5E5EA),

          // ── Semantic labels ────────────────────────────────────────────────
          primaryLabel: isDark ? Colors.white : const Color(0xFF111111),
          secondaryLabel: isDark
              ? const Color(0xFF8E8E93)
              : const Color(0xFF6C6C70),
          tertiaryLabel: isDark
              ? const Color(0xFF636366)
              : const Color(0xFF8E8E93),
          quaternaryLabel: isDark
              ? const Color(0xFF48484A)
              : const Color(0xFFAEAEB2),
          dimLabel: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFC7C7CC),

          // ── Separators ─────────────────────────────────────────────────────
          separator: isDark ? const Color(0xFF48484A) : const Color(0xFFC6C6C8),
          subtleSeparator: isDark
              ? const Color(0xFF38383A)
              : const Color(0xFFD1D1D6),
          hairlineSeparator: isDark
              ? const Color(0xFF111111)
              : const Color(0xFFE5E5EA),

          // ── Glass components ───────────────────────────────────────────────
          // Lighter tint so the backdrop reads as clear glass instead of a
          // filled surface. Both the pill navbar and mini player consume these
          // same tokens, keeping their glass material visually consistent.
          glassNavTint: isDark
              ? Colors.white.withValues(alpha: 0.02)
              : Colors.white.withValues(alpha: 0.45),
          glassBorderTint: isDark
              // Abu netral (secondaryLabel) + alpha lebih rendah — bukan putih
              // murni, jadi outline pill mini player & navbar tidak lagi terbaca
              // sebagai garis putih di dark mode.
              ? const Color(0xFF8E8E93).withValues(alpha: 0.12)
              // Light mode: abu netral (secondaryLabel light) pengganti hitam
              // murni — outline tidak lagi terbaca sebagai garis hitam mencolok.
              : const Color(0xFF6C6C70).withValues(alpha: 0.18),

          // ── Drag handle ────────────────────────────────────────────────────
          dragHandle: isDark
              ? Colors.white.withValues(alpha: 0.24)
              : Colors.black.withValues(alpha: 0.15),

          // ── Equalizer ──────────────────────────────────────────────────────
          eqTrackBg: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFD1D1D6),
          eqCenterTick: isDark
              ? const Color(0xFF636366)
              : const Color(0xFF8E8E93),
          eqDisabledColor: isDark
              ? const Color(0xFF3A3A3C)
              : const Color(0xFFD1D1D6),
        ),
      ],
    );
  }

  static final ThemeData dark = _base(brightness: Brightness.dark);
  static final ThemeData light = _base(brightness: Brightness.light);
}
