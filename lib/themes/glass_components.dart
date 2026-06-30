import 'dart:ui';
import 'package:flutter/material.dart';
import 'theme_controller.dart';

/// Widget pembungkus yang menerapkan efek liquid glass pada komponen manapun.
/// RepaintBoundary mengisolasi BackdropFilter agar tidak rekomposit saat
/// widget lain di luar boundary berubah.
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double sigmaBlur;
  final double tintOpacity;
  final BoxDecoration? decoration;

  const GlassContainer({
    super.key,
    required this.child,
    this.sigmaBlur = 28,
    this.tintOpacity = 0.055,
    this.decoration,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: sigmaBlur, sigmaY: sigmaBlur),
                child: DecoratedBox(
                  decoration:
                      decoration ??
                      BoxDecoration(
                        color: Colors.white.withValues(alpha: tintOpacity),
                      ),
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Versi reactive: otomatis aktif/nonaktif berdasarkan ThemeController.glassTheme.
class GlassWidget extends StatelessWidget {
  final Widget child;
  final Widget? fallback;
  final double sigmaBlur;
  final double tintOpacity;
  final BoxDecoration? decoration;

  const GlassWidget({
    super.key,
    required this.child,
    this.fallback,
    this.sigmaBlur = 28,
    this.tintOpacity = 0.055,
    this.decoration,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ThemeController.glassTheme,
      builder: (context, isGlass, _) {
        if (!isGlass) return fallback ?? child;
        return GlassContainer(
          sigmaBlur: sigmaBlur,
          tintOpacity: tintOpacity,
          decoration: decoration,
          child: child,
        );
      },
    );
  }
}
