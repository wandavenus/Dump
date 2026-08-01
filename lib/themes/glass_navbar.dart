import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:musicplayer/theme/app_colors.dart';

class GlassNavBar extends StatelessWidget {
  final Widget child;

  const GlassNavBar({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Stack(
      children: [
        // RepaintBoundary isolates the BackdropFilter so it is not
        // recomposited when navigation items or overlying widgets change.
        Positioned.fill(
          child: RepaintBoundary(
            child: ClipRect(
              child: BackdropFilter(
                // Keep the backdrop radius modest: this filter is recomputed
                // while content scrolls behind the navbar. A large sigma is
                // disproportionately expensive on the target Snapdragon 730.
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                blendMode: BlendMode.srcOver,
                child: Container(color: c.glassNavTint),
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 0.5,
          child: Container(color: c.glassBorderTint),
        ),
        child,
      ],
    );
  }
}
