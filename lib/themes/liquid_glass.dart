import 'dart:ui';
import 'package:flutter/material.dart';

/// Design tokens untuk iOS 27 Liquid Glass.
class LiquidGlassTokens {
  const LiquidGlassTokens._();

  static const double blurSigma = 24.0;
  static const double barBlurSigma = 20.0;
  static const double borderWidth = 0.75;
  static const double topHighlight = 0.30;
  static const double midHighlight = 0.10;
  static const double bottomFill = 0.04;
  static const double borderOpacity = 0.22;
  static const double shadowOpacity = 0.22;
}

/// Kontainer kaca utama — panel rounded dengan blur + specular highlight diagonal.
/// Setara dengan surface glass di iOS 27.
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.blur = LiquidGlassTokens.blurSigma,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.addShadow = true,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double blur;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final bool addShadow;

  @override
  Widget build(BuildContext context) {
    final glassLayer = ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(LiquidGlassTokens.topHighlight),
                Colors.white.withOpacity(LiquidGlassTokens.midHighlight),
                Colors.white.withOpacity(LiquidGlassTokens.bottomFill),
              ],
              stops: const [0.0, 0.45, 1.0],
            ),
            border: Border.all(
              color: Colors.white.withOpacity(LiquidGlassTokens.borderOpacity),
              width: LiquidGlassTokens.borderWidth,
            ),
          ),
          child: child,
        ),
      ),
    );

    if (!addShadow) {
      return Container(margin: margin, width: width, height: height, child: glassLayer);
    }

    return Container(
      margin: margin,
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(LiquidGlassTokens.shadowOpacity),
            blurRadius: 28,
            spreadRadius: -4,
            offset: const Offset(0, 8),
          ),
          // Specular outer glow (atas)
          BoxShadow(
            color: Colors.white.withOpacity(0.04),
            blurRadius: 0,
            spreadRadius: 0,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: glassLayer,
    );
  }
}

/// Bar kaca penuh lebar — untuk AppBar, header, bottom bar.
/// Tidak punya border radius (clip oleh parent).
class LiquidGlassBar extends StatelessWidget {
  const LiquidGlassBar({
    super.key,
    this.blur = LiquidGlassTokens.barBlurSigma,
    this.showBottomBorder = true,
    this.showTopBorder = false,
    this.child,
  });

  final double blur;
  final bool showBottomBorder;
  final bool showTopBorder;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withOpacity(0.22),
                Colors.white.withOpacity(0.06),
              ],
            ),
            border: Border(
              top: showTopBorder
                  ? BorderSide(color: Colors.white.withOpacity(0.35), width: 0.5)
                  : BorderSide.none,
              bottom: showBottomBorder
                  ? BorderSide(color: Colors.white.withOpacity(0.14), width: 0.5)
                  : BorderSide.none,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Pill / capsule glass kecil untuk chip, tag, atau tombol kecil.
class LiquidGlassPill extends StatelessWidget {
  const LiquidGlassPill({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      borderRadius: const BorderRadius.all(Radius.circular(50)),
      padding: padding,
      addShadow: false,
      child: child,
    );
  }
}
