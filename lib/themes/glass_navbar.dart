import 'package:flutter/material.dart';

import 'apple_music_material.dart';

class GlassNavBar extends StatelessWidget {
  final Widget child;

  const GlassNavBar({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AppleMusicMaterial(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      borderRadius: BorderRadius.circular(30),
      style: AppleMusicMaterialStyle.regular,
      showShadow: true,
      child: child,
    );
  }
}
