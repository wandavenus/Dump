import 'package:flutter/material.dart';

/// Relative luminance above which dark text is more readable than white.
///
/// 0.179 is the W3C switch point where black and white have equal contrast.
const double _kDarkTextLuminanceThreshold = 0.179;

/// Returns a readable primary text color for [background].
///
/// Native palettes may contain very light primaries (white/gray artwork), so
/// hardcoding white text can make album cards unreadable.
Color paletteForegroundColor(Color background) =>
    background.computeLuminance() > _kDarkTextLuminanceThreshold
    ? Colors.black87
    : Colors.white;

/// Returns a readable secondary text color for [background].
Color paletteSecondaryForegroundColor(Color background) =>
    background.computeLuminance() > _kDarkTextLuminanceThreshold
    ? Colors.black54
    : Colors.white70;
