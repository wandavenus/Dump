import 'package:flutter/material.dart';

class AppIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color? backgroundColor;
  final Color? iconColor;
  final double? size;
  final double? iconSize;

  const AppIconButton({
    Key? key,
    required this.icon,
    required this.onPressed,
    this.backgroundColor,
    this.iconColor,
    this.size = 50,
    this.iconSize = 20,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(150),
        color: backgroundColor ?? const Color.fromARGB(85, 158, 158, 158),
      ),
      child: GestureDetector(
        onTap: onPressed,
        child: Icon(
          icon,
          size: iconSize,
          color: iconColor ?? Colors.white,
        ),
      ),
    );
  }
}