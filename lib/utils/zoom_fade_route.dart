import 'package:flutter/material.dart';

/// Transisi bergaya iOS Music:
/// - Incoming: fade in + scale 0.95 → 1.0
/// - Outgoing (halaman di bawah): scale 1.0 → 0.95 + slight fade
/// - Tidak ada slide horizontal sama sekali
/// LyricsOverlay & QueueOverlay di dalam PlayerSheet dikecualikan
/// karena tidak menggunakan Navigator.
class ZoomFadeRoute<T> extends PageRouteBuilder<T> {
  final Widget page;

  ZoomFadeRoute({required this.page, super.settings})
      : super(
          transitionDuration: const Duration(milliseconds: 350),
          reverseTransitionDuration: const Duration(milliseconds: 280),
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            // Halaman ini sedang masuk (push: 0→1, pop: 1→0)
            final inCurve = CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOut,
            );

            // Halaman ini sedang ditimpa oleh route baru di atasnya (0→1)
            final outCurve = CurvedAnimation(
              parent: secondaryAnimation,
              curve: Curves.easeInOut,
            );

            return FadeTransition(
              opacity: Tween<double>(begin: 1.0, end: 0.85).animate(outCurve),
              child: ScaleTransition(
                scale: Tween<double>(begin: 1.0, end: 0.95).animate(outCurve),
                child: FadeTransition(
                  opacity:
                      Tween<double>(begin: 0.0, end: 1.0).animate(inCurve),
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.95, end: 1.0)
                        .animate(inCurve),
                    child: child,
                  ),
                ),
              ),
            );
          },
        );
}
