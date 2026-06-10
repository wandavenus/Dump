import 'dart:ui';

import 'package:flutter/material.dart';

class GlassNavBar extends StatelessWidget {
  final Widget child;
  final Color accent;

  const GlassNavBar({
    super.key,
    required this.child,
    this.accent = const Color(0xFFF92D48),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              color: Colors.white.withOpacity(0.095),
              border: Border.all(color: Colors.white.withOpacity(0.18)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.28),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
                BoxShadow(
                  color: accent.withOpacity(0.16),
                  blurRadius: 36,
                  offset: const Offset(0, -8),
                ),
              ],
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(0.18),
                  Colors.white.withOpacity(0.06),
                  accent.withOpacity(0.08),
                ],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
