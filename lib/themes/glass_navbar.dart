import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:musicplayer/theme/app_colors.dart';
import 'package:musicplayer/themes/app_theme_extension.dart';
import 'package:musicplayer/themes/theme_controller.dart';

const double kMiniPlayerHeight = 64.5;

double navBottomClearance(BuildContext context) {
  final safeBottom = MediaQuery.paddingOf(context).bottom;
  final isGlass = ThemeController.glassTheme.value;
  final navStyle = ThemeController.navBarStyle.value;
  if (isGlass && navStyle == NavBarStyle.pill) {
    return FloatingPillNavBar.bodyHeight +
        FloatingPillNavBar.bottomGap +
        FloatingPillNavBar.miniPlayerGap +
        kMiniPlayerHeight +
        safeBottom +
        10.7;
  }
  final navBarH = isGlass && navStyle != NavBarStyle.solid ? 53.8 : 55.1;
  return navBarH + kMiniPlayerHeight + safeBottom + 10.7;
}

class GlassNavBar extends StatelessWidget {
  final Widget child;

  const GlassNavBar({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                blendMode: BlendMode.srcOver,
                child: const ColoredBox(color: Colors.transparent),
              ),
            ),
          ),
        ),
        Positioned.fill(child: ColoredBox(color: c.glassFillTint)),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 0.5,
          child: ColoredBox(color: c.glassBorderTint),
        ),
        child,
      ],
    );
  }
}

/// Navbar kapsul apung gaya iOS 26 (Liquid Glass).
class FloatingPillNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final List<IconData> icons;
  final List<String?> labels;
  final List<String>? semanticsLabels;
  final IconData? trailingIcon;
  final String? trailingLabel;

  const FloatingPillNavBar({
    super.key,
    required this.selectedIndex,
    required this.onTap,
    required this.icons,
    required this.labels,
    this.semanticsLabels,
    this.trailingIcon,
    this.trailingLabel,
  });

  static const double bodyHeight = 62.0;
  static const double horizMargin = 14.0;
  static const double bottomGap = 10.0;
  static const double miniPlayerGap = 10.0;
  static const double trailingGap = 10.0;
  static const double trailingSize = bodyHeight;
  static const double _iconSize = 24.0;

  static final ImageFilter _pillBlur = ImageFilter.blur(
    sigmaX: 12,
    sigmaY: 12,
  );

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final radius = bodyHeight / 2;

    return BackdropGroup(
      child: Stack(
        children: [
          // Full-width floating shadow beneath the entire navigation area.
          // It spans edge-to-edge rather than following the outer pill shape.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 110,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      (Theme.of(context).brightness == Brightness.dark
                              ? Colors.black
                              : Colors.white)
                          .withValues(alpha: 0.10),
                      (Theme.of(context).brightness == Brightness.dark
                              ? Colors.black
                              : Colors.white)
                          .withValues(alpha: 0.18),
                    ],
                    stops: const [0.0, 0.42, 1.0],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              horizMargin,
              0,
              horizMargin,
              bottomGap + safeBottom,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: _buildCapsule(context, c, radius)),
                if (trailingIcon != null) ...[
                  const SizedBox(width: trailingGap),
                  _TrailingButton(
                    icon: trailingIcon!,
                    label: trailingLabel,
                    active: selectedIndex == icons.length,
                    onTap: () => onTap(icons.length),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCapsule(
    BuildContext context,
    AppThemeExtension c,
    double radius,
  ) {
    return SizedBox(
      width: double.infinity,
      height: bodyHeight,
      child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            fit: StackFit.expand,
          children: [
            ClipRect(
              child: BackdropFilter.grouped(
                filter: FloatingPillNavBar._pillBlur,
                blendMode: BlendMode.srcOver,
                child: const ColoredBox(color: Colors.transparent),
              ),
            ),
            ColoredBox(color: c.glassFillTint),
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(color: c.glassBorderTint, width: 1),
                ),
              ),
            ),
            _PillItems(
              selectedIndex: selectedIndex,
              onTap: onTap,
              icons: icons,
              labels: labels,
              semanticsLabels: semanticsLabels,
            ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PillItems extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final List<IconData> icons;
  final List<String?> labels;
  final List<String>? semanticsLabels;

  const _PillItems({
    required this.selectedIndex,
    required this.onTap,
    required this.icons,
    required this.labels,
    this.semanticsLabels,
  });

  @override
  Widget build(BuildContext context) {
    final count = icons.length;
    return SizedBox(
      height: FloatingPillNavBar.bodyHeight,
      child: Row(
        children: [
          for (var i = 0; i < count; i++)
            Expanded(
              child: _PillItem(
                icon: icons[i],
                label: labels[i],
                semanticsLabel: semanticsLabels != null
                    ? semanticsLabels![i]
                    : labels[i],
                active: i == selectedIndex,
                onTap: () => onTap(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _PillItem extends StatelessWidget {
  final IconData icon;
  final String? label;
  final String? semanticsLabel;
  final bool active;
  final VoidCallback onTap;

  const _PillItem({
    required this.icon,
    required this.label,
    required this.semanticsLabel,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final color = active ? primary : c.secondaryLabel;

    return Semantics(
      button: true,
      selected: active,
      label: semanticsLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 5),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: active ? c.glassActiveLens : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(FloatingPillNavBar._iconSize == 24
                      ? icon
                      : icon, size: FloatingPillNavBar._iconSize, color: color),
                  if (label != null) ...[
                    const SizedBox(height: 3),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label!,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 11,
                          color: color,
                          fontWeight:
                              active ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrailingButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final bool active;
  final VoidCallback onTap;

  const _TrailingButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ClipOval(
          child: SizedBox(
            width: FloatingPillNavBar.trailingSize,
            height: FloatingPillNavBar.trailingSize,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRect(
                  child: BackdropFilter.grouped(
                    filter: FloatingPillNavBar._pillBlur,
                    blendMode: BlendMode.srcOver,
                    child: const ColoredBox(color: Colors.transparent),
                  ),
                ),
                ColoredBox(color: c.glassFillTint),
                DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: c.glassBorderTint, width: 1),
                  ),
                ),
                Center(
                  child: Icon(
                    icon,
                    size: FloatingPillNavBar._iconSize,
                    color: active ? primary : c.secondaryLabel,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
