import 'package:flutter/material.dart';

class WebView extends StatelessWidget {
  final Widget? child;
  final Color innerContainerColor;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final List<Color> gradientColors;
  final List<double> gradientStops;

  const WebView({
    super.key,
    this.child,
    this.innerContainerColor = Colors.black87,
    this.borderRadius = 0.0,
    this.padding = EdgeInsets.zero,
    this.gradientColors = const [Color(0xff536976), Color(0xff292e49)],
    this.gradientStops = const [0, 1],
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors,
            stops: gradientStops,
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Padding(
            padding: padding,
            child: Container(
              height: double.infinity,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.all(Radius.circular(borderRadius)),
                color: innerContainerColor,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.all(Radius.circular(borderRadius)),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
