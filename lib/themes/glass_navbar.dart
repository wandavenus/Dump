import 'package:flutter/material.dart';
import 'liquid_glass.dart';

/// Nav bar Liquid Glass gaya iOS 27 — pill floating dengan specular highlight.
class GlassNavBar extends StatelessWidget {
  final Widget child;

  const GlassNavBar({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: LiquidGlass(
        borderRadius: BorderRadius.circular(28),
        blur: LiquidGlassTokens.blurSigma,
        addShadow: true,
        child: child,
      ),
    );
  }
}
