import 'package:flutter/material.dart';

import 'apple_music_blur.dart';

class GlassNavBar extends StatelessWidget {
  final Widget child;

  const GlassNavBar({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: AppleMusicMaterial(
        style: AppleMusicMaterialStyle.regular,
        borderRadius: BorderRadius.circular(AppleMusicRadii.floating),
        padding: const EdgeInsets.only(top: 2),
        child: child,
      ),
    );
  }
}
