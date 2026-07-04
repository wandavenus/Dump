import 'package:flutter/material.dart';

/// Transisi pure fade — tidak ada zoom, scale, maupun slide.
/// LyricsOverlay & QueueOverlay di dalam PlayerSheet dikecualikan
/// karena tidak menggunakan Navigator.
class ZoomFadeRoute<T> extends PageRouteBuilder<T> {
  final Widget page;

  ZoomFadeRoute({required this.page, super.settings})
      : super(
          transitionDuration: const Duration(milliseconds: 300),
          reverseTransitionDuration: const Duration(milliseconds: 250),
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeInOut,
              ),
              child: child,
            );
          },
        );
}
