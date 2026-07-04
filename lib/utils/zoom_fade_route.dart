import 'package:flutter/material.dart';

/// PageRoute yang menggunakan animasi zoom + fade.
/// Dipakai untuk semua navigasi halaman di app.
/// LyricsOverlay dan QueueOverlay di dalam PlayerSheet dikecualikan
/// karena tidak menggunakan Navigator sama sekali.
class ZoomFadeRoute<T> extends PageRouteBuilder<T> {
  final Widget page;

  ZoomFadeRoute({required this.page, super.settings})
      : super(
          transitionDuration: const Duration(milliseconds: 280),
          reverseTransitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (context, animation, _) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
                child: child,
              ),
            );
          },
        );
}
