import 'dart:ui';

import 'package:flutter/material.dart';

@immutable
class AppThemeExtension extends ThemeExtension<AppThemeExtension> {
  const AppThemeExtension({
    // ── Original glass fields ────────────────────────────────────────────────
    required this.glassColor,
    required this.glassOpacity,
    required this.artworkOverlay,
    // ── Surface hierarchy ────────────────────────────────────────────────────
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.codeBackground,
    // ── Semantic labels ──────────────────────────────────────────────────────
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.tertiaryLabel,
    required this.quaternaryLabel,
    required this.dimLabel,
    // ── Separators ───────────────────────────────────────────────────────────
    required this.separator,
    required this.subtleSeparator,
    required this.hairlineSeparator,
    // ── Glass components ─────────────────────────────────────────────────────
    required this.glassNavTint,
    required this.glassBorderTint,
    // ── Drag handle ──────────────────────────────────────────────────────────
    required this.dragHandle,
    // ── Equalizer ────────────────────────────────────────────────────────────
    required this.eqTrackBg,
    required this.eqCenterTick,
    required this.eqDisabledColor,
  });

  // Original glass
  final Color  glassColor;
  final double glassOpacity;
  final Color  artworkOverlay;

  // Surface hierarchy
  /// Card / bottom-sheet background.
  final Color surface;
  /// Secondary surface — nested cards, snack bar.
  final Color surface2;
  /// Tertiary surface — subtle fills, track backgrounds.
  final Color surface3;
  /// Monospace / code panel background (log page stack traces).
  final Color codeBackground;

  // Semantic labels
  /// Primary body text.
  final Color primaryLabel;
  /// Secondary text, icon tint.
  final Color secondaryLabel;
  /// Tertiary / placeholder text.
  final Color tertiaryLabel;
  /// Very dim text — counts, timestamps.
  final Color quaternaryLabel;
  /// Nearly invisible — decorative.
  final Color dimLabel;

  // Separators
  /// Standard hairline divider.
  final Color separator;
  /// Subtle divider — between nav sections.
  final Color subtleSeparator;
  /// Very faint row divider — log entries.
  final Color hairlineSeparator;

  // Glass components
  /// Color wash rendered inside the glass BackdropFilter container.
  final Color glassNavTint;
  /// Top/bottom border on glass surfaces.
  final Color glassBorderTint;

  // Misc
  /// Pill drag handle on bottom sheets.
  final Color dragHandle;
  /// EQ band track background.
  final Color eqTrackBg;
  /// EQ center (0 dB) tick mark.
  final Color eqCenterTick;
  /// EQ track color when equalizer is disabled.
  final Color eqDisabledColor;

  @override
  AppThemeExtension copyWith({
    Color?  glassColor,
    double? glassOpacity,
    Color?  artworkOverlay,
    Color?  surface,
    Color?  surface2,
    Color?  surface3,
    Color?  codeBackground,
    Color?  primaryLabel,
    Color?  secondaryLabel,
    Color?  tertiaryLabel,
    Color?  quaternaryLabel,
    Color?  dimLabel,
    Color?  separator,
    Color?  subtleSeparator,
    Color?  hairlineSeparator,
    Color?  glassNavTint,
    Color?  glassBorderTint,
    Color?  dragHandle,
    Color?  eqTrackBg,
    Color?  eqCenterTick,
    Color?  eqDisabledColor,
  }) => AppThemeExtension(
    glassColor:        glassColor       ?? this.glassColor,
    glassOpacity:      glassOpacity     ?? this.glassOpacity,
    artworkOverlay:    artworkOverlay   ?? this.artworkOverlay,
    surface:           surface          ?? this.surface,
    surface2:          surface2         ?? this.surface2,
    surface3:          surface3         ?? this.surface3,
    codeBackground:    codeBackground   ?? this.codeBackground,
    primaryLabel:      primaryLabel     ?? this.primaryLabel,
    secondaryLabel:    secondaryLabel   ?? this.secondaryLabel,
    tertiaryLabel:     tertiaryLabel    ?? this.tertiaryLabel,
    quaternaryLabel:   quaternaryLabel  ?? this.quaternaryLabel,
    dimLabel:          dimLabel         ?? this.dimLabel,
    separator:         separator        ?? this.separator,
    subtleSeparator:   subtleSeparator  ?? this.subtleSeparator,
    hairlineSeparator: hairlineSeparator ?? this.hairlineSeparator,
    glassNavTint:      glassNavTint     ?? this.glassNavTint,
    glassBorderTint:   glassBorderTint  ?? this.glassBorderTint,
    dragHandle:        dragHandle       ?? this.dragHandle,
    eqTrackBg:         eqTrackBg        ?? this.eqTrackBg,
    eqCenterTick:      eqCenterTick     ?? this.eqCenterTick,
    eqDisabledColor:   eqDisabledColor  ?? this.eqDisabledColor,
  );

  @override
  AppThemeExtension lerp(ThemeExtension<AppThemeExtension>? other, double t) {
    if (other is! AppThemeExtension) return this;
    return AppThemeExtension(
      glassColor:        Color.lerp(glassColor,        other.glassColor,        t)!,
      glassOpacity:      lerpDouble(glassOpacity,      other.glassOpacity,      t)!,
      artworkOverlay:    Color.lerp(artworkOverlay,    other.artworkOverlay,    t)!,
      surface:           Color.lerp(surface,           other.surface,           t)!,
      surface2:          Color.lerp(surface2,          other.surface2,          t)!,
      surface3:          Color.lerp(surface3,          other.surface3,          t)!,
      codeBackground:    Color.lerp(codeBackground,    other.codeBackground,    t)!,
      primaryLabel:      Color.lerp(primaryLabel,      other.primaryLabel,      t)!,
      secondaryLabel:    Color.lerp(secondaryLabel,    other.secondaryLabel,    t)!,
      tertiaryLabel:     Color.lerp(tertiaryLabel,     other.tertiaryLabel,     t)!,
      quaternaryLabel:   Color.lerp(quaternaryLabel,   other.quaternaryLabel,   t)!,
      dimLabel:          Color.lerp(dimLabel,          other.dimLabel,          t)!,
      separator:         Color.lerp(separator,         other.separator,         t)!,
      subtleSeparator:   Color.lerp(subtleSeparator,   other.subtleSeparator,   t)!,
      hairlineSeparator: Color.lerp(hairlineSeparator, other.hairlineSeparator, t)!,
      glassNavTint:      Color.lerp(glassNavTint,      other.glassNavTint,      t)!,
      glassBorderTint:   Color.lerp(glassBorderTint,   other.glassBorderTint,   t)!,
      dragHandle:        Color.lerp(dragHandle,        other.dragHandle,        t)!,
      eqTrackBg:         Color.lerp(eqTrackBg,         other.eqTrackBg,         t)!,
      eqCenterTick:      Color.lerp(eqCenterTick,      other.eqCenterTick,      t)!,
      eqDisabledColor:   Color.lerp(eqDisabledColor,   other.eqDisabledColor,   t)!,
    );
  }
}
