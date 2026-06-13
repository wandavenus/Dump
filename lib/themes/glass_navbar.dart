import 'dart:ui';
import 'package:flutter/material.dart';

class GlassNavBar extends StatelessWidget {
  final Widget child;

  const GlassNavBar({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Container(
                color: Colors.white.withOpacity(0.055),
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 1.0,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                stops: const [0.0, 0.38, 0.62, 1.0],
                colors: [
                  const Color(0x44FF2D55),
                  const Color(0x55FFFFFF),
                  const Color(0x55FFFFFF),
                  const Color(0x442979FF),
                ],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
