import 'package:flutter/material.dart';
import '../themes/theme_controller.dart';

/// WebView container yang glass-aware.
/// Saat Liquid Glass aktif: gradient biru-gelap muncul sebagai background
/// sehingga semua elemen glass punya sesuatu untuk di-blur.
class WebView extends StatefulWidget {
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
    this.innerContainerColor = Colors.black87,
    this.borderRadius = 0.0,
    this.padding = EdgeInsets.zero,
    this.gradientColors = const [
      Color(0xff536976),
      Color(0xff292e49),
    ],
    this.gradientStops = const [0, 1],
  });

  @override
  State<WebView> createState() => _WebViewState();
}

class _WebViewState extends State<WebView> {
  @override
  void initState() {
    super.initState();
    ThemeController.glassTheme.addListener(_onGlassChange);
  }

  @override
  void dispose() {
    ThemeController.glassTheme.removeListener(_onGlassChange);
    super.dispose();
  }

  void _onGlassChange() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final isGlass = ThemeController.glassTheme.value;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: isGlass
              ? const LinearGradient(
                  colors: [
                    Color(0xFF141B2D),
                    Color(0xFF090D16),
                    Color(0xFF141B2D),
                  ],
                  stops: [0.0, 0.5, 1.0],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : LinearGradient(
                  colors: widget.gradientColors,
                  stops: widget.gradientStops,
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
        ),
        child: Center(
          child: Padding(
            padding: widget.padding,
            child: Container(
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                // Glass mode: transparan agar gradient di atas terlihat.
                color: isGlass ? Colors.transparent : widget.innerContainerColor,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
