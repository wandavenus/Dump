import 'dart:ui';

import 'package:flutter/material.dart';

class AppleMusicColors {
  const AppleMusicColors._();

  static const accent = Color(0xFFFF2D55);
  static const backgroundTop = Color(0xFF151518);
  static const backgroundBottom = Color(0xFF050506);
  static const materialTint = Color(0xFFFFFFFF);
  static const materialDarkTint = Color(0xFF1C1C1E);
  static const separator = Color(0x29FFFFFF);
  static const primaryText = Color(0xFFF8F8F8);
  static const secondaryText = Color(0xB8FFFFFF);
  static const tertiaryText = Color(0x73FFFFFF);
}

class AppleMusicRadii {
  const AppleMusicRadii._();

  static const small = 12.0;
  static const medium = 18.0;
  static const large = 26.0;
  static const xLarge = 34.0;
  static const continuous = BorderRadius.all(Radius.circular(28));
}

enum AppleMusicMaterialStyle {
  ultraThin,
  thin,
  regular,
  prominent,
}

class AppleMusicMaterial extends StatelessWidget {
  final Widget child;
  final AppleMusicMaterialStyle style;
  final BorderRadiusGeometry borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final bool showBorder;
  final bool showShadow;
  final Color? tint;

  const AppleMusicMaterial({
    super.key,
    required this.child,
    this.style = AppleMusicMaterialStyle.regular,
    this.borderRadius = AppleMusicRadii.continuous,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.showBorder = true,
    this.showShadow = true,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final spec = _AppleMusicMaterialSpec.forStyle(style);
    final effectiveTint = tint ?? spec.tint;

    Widget current = ClipRRect(
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: spec.blur,
          sigmaY: spec.blur,
        ),
        child: Container(
          width: width,
          height: height,
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            color: effectiveTint.withOpacity(spec.opacity),
            border: showBorder
                ? Border.all(
                    color: Colors.white.withOpacity(spec.borderOpacity),
                    width: 0.8,
                  )
                : null,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(spec.highlightOpacity),
                effectiveTint.withOpacity(spec.opacity * 0.76),
                Colors.black.withOpacity(spec.depthOpacity),
              ],
              stops: const [0.0, 0.58, 1.0],
            ),
          ),
          child: child,
        ),
      ),
    );

    if (showShadow) {
      current = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(spec.shadowOpacity),
              blurRadius: spec.shadowBlur,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: current,
      );
    }

    if (margin != null) {
      current = Padding(padding: margin!, child: current);
    }

    return current;
  }
}

class AppleMusicPageBackground extends StatelessWidget {
  final Widget child;
  final List<Color>? accentColors;

  const AppleMusicPageBackground({
    super.key,
    required this.child,
    this.accentColors,
  });

  @override
  Widget build(BuildContext context) {
    final accents = accentColors ??
        const [
          Color(0x22FF2D55),
          Color(0x143B82F6),
        ];

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            AppleMusicColors.backgroundTop,
            AppleMusicColors.backgroundBottom,
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.75, -0.95),
                radius: 0.9,
                colors: [
                  accents.first,
                  Colors.transparent,
                ],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.85, -0.2),
                radius: 0.85,
                colors: [
                  accents.last,
                  Colors.transparent,
                ],
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class AppleMusicDivider extends StatelessWidget {
  final EdgeInsetsGeometry margin;

  const AppleMusicDivider({
    super.key,
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Container(
        height: 0.7,
        color: AppleMusicColors.separator,
      ),
    );
  }
}

class _AppleMusicMaterialSpec {
  final double blur;
  final double opacity;
  final double borderOpacity;
  final double highlightOpacity;
  final double depthOpacity;
  final double shadowOpacity;
  final double shadowBlur;
  final Color tint;

  const _AppleMusicMaterialSpec({
    required this.blur,
    required this.opacity,
    required this.borderOpacity,
    required this.highlightOpacity,
    required this.depthOpacity,
    required this.shadowOpacity,
    required this.shadowBlur,
    required this.tint,
  });

  factory _AppleMusicMaterialSpec.forStyle(AppleMusicMaterialStyle style) {
    switch (style) {
      case AppleMusicMaterialStyle.ultraThin:
        return const _AppleMusicMaterialSpec(
          blur: 22,
          opacity: 0.09,
          borderOpacity: 0.10,
          highlightOpacity: 0.09,
          depthOpacity: 0.04,
          shadowOpacity: 0.10,
          shadowBlur: 18,
          tint: AppleMusicColors.materialTint,
        );
      case AppleMusicMaterialStyle.thin:
        return const _AppleMusicMaterialSpec(
          blur: 28,
          opacity: 0.12,
          borderOpacity: 0.12,
          highlightOpacity: 0.11,
          depthOpacity: 0.05,
          shadowOpacity: 0.12,
          shadowBlur: 22,
          tint: AppleMusicColors.materialTint,
        );
      case AppleMusicMaterialStyle.regular:
        return const _AppleMusicMaterialSpec(
          blur: 34,
          opacity: 0.16,
          borderOpacity: 0.13,
          highlightOpacity: 0.13,
          depthOpacity: 0.07,
          shadowOpacity: 0.14,
          shadowBlur: 26,
          tint: AppleMusicColors.materialTint,
        );
      case AppleMusicMaterialStyle.prominent:
        return const _AppleMusicMaterialSpec(
          blur: 42,
          opacity: 0.22,
          borderOpacity: 0.16,
          highlightOpacity: 0.16,
          depthOpacity: 0.08,
          shadowOpacity: 0.18,
          shadowBlur: 32,
          tint: AppleMusicColors.materialTint,
        );
    }
  }
}
