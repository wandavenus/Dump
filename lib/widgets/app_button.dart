import 'package:flutter/material.dart';

import '../themes/apple_music_material.dart';

class AppButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final Color? backgroundColor;
  final Color? textColor;
  final Color? iconColor;
  final double? width;
  final double? height;

  const AppButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.backgroundColor,
    this.textColor,
    this.iconColor,
    this.width = 160,
    this.height = 50,
  });

  @override
  Widget build(BuildContext context) {
    return AppleMusicMaterial(
      width: width,
      height: height,
      borderRadius: BorderRadius.circular(18),
      style: AppleMusicMaterialStyle.thin,
      tint: backgroundColor,
      showShadow: false,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onPressed,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: iconColor ?? AppleMusicColors.accent,
                size: 26,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: textColor ?? AppleMusicColors.accent,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
