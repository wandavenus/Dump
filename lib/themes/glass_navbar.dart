import 'dart:ui';
import 'package:flutter/material.dart';

class GlassNavBar extends StatelessWidget {
  final Widget child;

  const GlassNavBar({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // RepaintBoundary isolates the BackdropFilter so it is not
        // recomposited when navigation items or overlying widgets change.
        Positioned.fill(
          child: RepaintBoundary(
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                child: Container(color: Colors.white.withValues(alpha: 0.055)),
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 0.5,
          child: Container(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child,
      ],
    );
  }
}
