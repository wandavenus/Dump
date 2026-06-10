import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';

class AppleMusicColors {
  const AppleMusicColors._();

  static const Color accent = Color(0xFFFF2D55);
  static const Color background = Color(0xFF050506);
  static const Color backgroundElevated = Color(0xFF111113);
  static const Color label = Colors.white;
  static const Color secondaryLabel = Color(0xB3FFFFFF);
  static const Color tertiaryLabel = Color(0x73FFFFFF);
  static const Color separator = Color(0x24FFFFFF);
  static const Color materialTint = Color(0xB8121216);
  static const Color regularMaterialTint = Color(0xCC17171B);
}

class AppleMusicRadii {
  const AppleMusicRadii._();

  static const double button = 18;
  static const double card = 22;
  static const double artwork = 28;
  static const double floating = 30;
  static const double sheet = 34;
}

class AppleMusicBlur {
  const AppleMusicBlur._();

  static const double ultraThin = 18;
  static const double thin = 24;
  static const double regular = 34;
  static const double prominent = 46;
}

enum AppleMusicMaterialStyle {
  ultraThin,
  regular,
  prominent,
}

class AppleMusicMaterial extends StatelessWidget {
  final Widget child;
  final AppleMusicMaterialStyle style;
  final BorderRadiusGeometry borderRadius;
  final EdgeInsetsGeometry padding;
  final bool showBorder;
  final bool showShadow;
  final Color? tint;
  final Clip clipBehavior;

  const AppleMusicMaterial({
    super.key,
    required this.child,
    this.style = AppleMusicMaterialStyle.regular,
    this.borderRadius = const BorderRadius.all(
      Radius.circular(AppleMusicRadii.card),
    ),
    this.padding = EdgeInsets.zero,
    this.showBorder = true,
    this.showShadow = true,
    this.tint,
    this.clipBehavior = Clip.antiAlias,
  });

  @override
  Widget build(BuildContext context) {
    final sigma = switch (style) {
      AppleMusicMaterialStyle.ultraThin => AppleMusicBlur.ultraThin,
      AppleMusicMaterialStyle.regular => AppleMusicBlur.regular,
      AppleMusicMaterialStyle.prominent => AppleMusicBlur.prominent,
    };

    final baseTint = tint ??
        switch (style) {
          AppleMusicMaterialStyle.ultraThin => AppleMusicColors.materialTint,
          AppleMusicMaterialStyle.regular => AppleMusicColors.regularMaterialTint,
          AppleMusicMaterialStyle.prominent => const Color(0xE01A1A1F),
        };

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: showShadow
            ? const [
                BoxShadow(
                  color: Color(0x52000000),
                  blurRadius: 26,
                  offset: Offset(0, 14),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        clipBehavior: clipBehavior,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: baseTint,
              borderRadius: borderRadius,
              border: showBorder
                  ? Border.all(color: const Color(0x1FFFFFFF), width: 0.8)
                  : null,
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x20FFFFFF),
                  Color(0x08FFFFFF),
                  Color(0x18000000),
                ],
              ),
            ),
            child: Padding(
              padding: padding,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class AppleMusicIconMaterial extends StatelessWidget {
  final Widget child;
  final double size;
  final VoidCallback? onTap;

  const AppleMusicIconMaterial({
    super.key,
    required this.child,
    this.size = 44,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppleMusicMaterial(
      style: AppleMusicMaterialStyle.ultraThin,
      borderRadius: BorderRadius.circular(size / 2),
      showShadow: false,
      child: SizedBox(
        width: size,
        height: size,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

class AppleMusicArtworkBackground extends StatelessWidget {
  final Uint8List? artwork;
  final double blurSigma;
  final double scale;

  const AppleMusicArtworkBackground({
    super.key,
    this.artwork,
    this.blurSigma = AppleMusicBlur.prominent,
    this.scale = 1.18,
  });

  @override
  Widget build(BuildContext context) {
    final data = artwork;
    final width = MediaQuery.of(context).size.width;
    final cacheWidth = (width * MediaQuery.of(context).devicePixelRatio / 2)
        .round()
        .clamp(240, 900)
        .toInt();

    return Stack(
      fit: StackFit.expand,
      children: [
        if (data == null || data.isEmpty)
          const _AppleMusicFallbackGradient()
        else
          Transform.scale(
            scale: scale,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
              child: Image.memory(
                data,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                cacheWidth: cacheWidth,
                filterQuality: FilterQuality.low,
              ),
            ),
          ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x66000000),
                Color(0x9A050506),
                Color(0xF2050506),
              ],
              stops: [0, 0.52, 1],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.topCenter,
              radius: 0.95,
              colors: [
                Color(0x33FFFFFF),
                Color(0x11000000),
                Color(0x00000000),
              ],
              stops: [0, 0.45, 1],
            ),
          ),
        ),
      ],
    );
  }
}

class _AppleMusicFallbackGradient extends StatelessWidget {
  const _AppleMusicFallbackGradient();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF2B1420),
            Color(0xFF14141A),
            Color(0xFF050506),
          ],
          stops: [0, 0.45, 1],
        ),
      ),
    );
  }
}

class AppleMusicPageBackdrop extends StatelessWidget {
  final Widget child;

  const AppleMusicPageBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF130A10),
            AppleMusicColors.background,
            Color(0xFF09090D),
          ],
          stops: [0, 0.42, 1],
        ),
      ),
      child: child,
    );
  }
}

class AppleMusicBarBackground extends StatelessWidget {
  final double opacity;

  const AppleMusicBarBackground({super.key, this.opacity = 1});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity.clamp(0.0, 1.0).toDouble(),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: AppleMusicBlur.regular,
            sigmaY: AppleMusicBlur.regular,
          ),
          child: const DecoratedBox(
            decoration: BoxDecoration(
              color: AppleMusicColors.materialTint,
              border: Border(
                bottom: BorderSide(color: AppleMusicColors.separator, width: 0.6),
              ),
            ),
            child: SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}
