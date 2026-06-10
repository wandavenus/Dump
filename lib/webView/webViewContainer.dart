import 'package:flutter/material.dart';

import '../themes/apple_music_material.dart';

class WebView extends StatelessWidget {
  final Widget? child;
  final double? innerContainerHeight;
  final double? innerContainerWidth;
  final Color shadowColor;
  final double shadowBlurRadius;
  final double shadowSpreadRadius;
  final Color innerContainerColor;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final List<Color> gradientColors;
  final List<double> gradientStops;

  const WebView({
    super.key,
    this.child,
    this.innerContainerHeight = 866,
    this.innerContainerWidth = 400,
    this.shadowColor = Colors.black54,
    this.shadowBlurRadius = 10.0,
    this.shadowSpreadRadius = 0.0,
    this.innerContainerColor = Colors.transparent,
    this.borderRadius = 0.0,
    this.padding = EdgeInsets.zero,
    this.gradientColors = const [
      AppleMusicColors.backgroundTop,
      AppleMusicColors.backgroundBottom,
    ],
    this.gradientStops = const [0, 1],
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppleMusicColors.backgroundBottom,
      body: AppleMusicPageBackground(
        child: Center(
          child: Padding(
            padding: padding,
            child: Container(
              height: double.infinity,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.all(
                  Radius.circular(borderRadius),
                ),
                color: innerContainerColor,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.all(
                  Radius.circular(borderRadius),
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
