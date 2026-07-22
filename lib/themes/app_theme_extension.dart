import 'package:flutter/material.dart';

@immutable
class AppThemeExtension extends ThemeExtension<AppThemeExtension> {
  final Color glassColor;
  final double glassOpacity;
  final Color artworkOverlay;

  const AppThemeExtension({
    required this.glassColor,
    required this.glassOpacity,
    required this.artworkOverlay,
  });

  @override
  AppThemeExtension copyWith({
    Color? glassColor,
    double? glassOpacity,
    Color? artworkOverlay,
  }) {
    return AppThemeExtension(
      glassColor: glassColor ?? this.glassColor,
      glassOpacity: glassOpacity ?? this.glassOpacity,
      artworkOverlay: artworkOverlay ?? this.artworkOverlay,
    );
  }

  @override
  AppThemeExtension lerp(ThemeExtension<AppThemeExtension>? other, double t) {
    if (other is! AppThemeExtension) return this;

    return AppThemeExtension(
      glassColor: Color.lerp(glassColor, other.glassColor, t)!,
      glassOpacity: lerpDouble(glassOpacity, other.glassOpacity, t)!,
      artworkOverlay: Color.lerp(artworkOverlay, other.artworkOverlay, t)!,
    );
  }
}
