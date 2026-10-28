import 'package:flutter/material.dart';
import 'package:musicplayer/theme/app_colors.dart';
import 'package:musicplayer/themes/theme_controller.dart';
import 'package:musicplayer/services/floating_pill_transition_controller.dart';

const double kMiniPlayerHeight = 62.0;

/// Soft neutral-gray tint inspired by Mornye's glass surfaces.
/// Keep navbar glass more transparent than the mini player, without changing
/// the other Liquid Glass components.
Color pillGlassSurfaceTint(
  BuildContext context, {
  bool miniPlayer = false,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final color = isDark
      ? const Color(0xFF2C2C2E)
      : const Color(0xFFF2F2F7);
  final opacity = isDark
      ? (miniPlayer ? 0.32 : 0.22)
      : (miniPlayer ? 0.38 : 0.28);
  return color.withValues(alpha: opacity);
}

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
        0.0;
  }
  return 55.1 + kMiniPlayerHeight + safeBottom + 10.7;
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

  static const ImageFilterConfig _pillBlurConfig = ImageFilterConfig.blur(
    sigmaX: 6,
    sigmaY: 6,
    bounded: true,
  );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: FloatingPillTransitionController.progress,
      builder: (context, compactProgress, _) =>
          _buildTransition(context, compactProgress),
    );
  }

  Widget _buildTransition(BuildContext context, double compactProgress) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final radius = bodyHeight / 2;
    final shadowColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.black
        : Colors.white;

    return BackdropGroup(
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: bottomGap + safeBottom + 82,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      shadowColor.withValues(alpha: 0.008),
                      shadowColor.withValues(alpha: 0.008),
                      shadowColor.withValues(alpha: 0.02),
                      shadowColor.withValues(alpha: 0.055),
                      shadowColor.withValues(alpha: 0.15),
                      shadowColor.withValues(alpha: 0.30),
                      shadowColor.withValues(alpha: 0.45),
                    ],
                    stops: const [0.0, 0.18, 0.34, 0.49, 0.66, 0.84, 1.0],
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                final availableWidth = constraints.maxWidth;
                final hasTrailing = trailingIcon != null;
                final normalCapsuleWidth = hasTrailing
                    ? availableWidth - trailingGap - trailingSize
                    : availableWidth;
                final capsuleWidth = normalCapsuleWidth +
                    (bodyHeight - normalCapsuleWidth) * compactProgress;
                final dockWidth = hasTrailing
                    ? (availableWidth -
                              bodyHeight -
                              trailingSize -
                              trailingGap * 2)
                          .clamp(0.0, availableWidth) *
                        compactProgress
                    : 0.0;

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Transform.scale(
                      scale: FloatingPillTransitionController.scaleForProgress(
                        compactProgress,
                      ),
                      child: SizedBox(
                        width: capsuleWidth,
                        height: bodyHeight,
                        child: _buildCapsule(
                          context,
                          radius,
                          compactProgress,
                        ),
                      ),
                    ),
                    SizedBox(width: trailingGap * compactProgress),
                    SizedBox(width: dockWidth),
                    if (hasTrailing) ...[
                      SizedBox(width: trailingGap),
                      Transform.scale(
                        scale:
                            FloatingPillTransitionController.scaleForProgress(
                              compactProgress,
                            ),
                        child: _TrailingButton(
                          icon: trailingIcon!,
                          label: trailingLabel,
                          active: selectedIndex == icons.length,
                          onTap: () => onTap(icons.length),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCapsule(
    BuildContext context,
    double radius,
    double compactProgress,
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
                filterConfig: const ImageFilterConfig.blur(
                  sigmaX: 6,
                  sigmaY: 6,
                  bounded: true,
                ),
                blendMode: BlendMode.srcOver,
                child: const ColoredBox(color: Colors.transparent),
              ),
            ),
            ColoredBox(color: pillGlassSurfaceTint(context)),
            IgnorePointer(
              child: CustomPaint(
                painter: PillGlassRimPainter(
                  radius: radius,
                  isDark: Theme.of(context).brightness == Brightness.dark,
                ),
              ),
            ),
            _PillItems(
              selectedIndex: selectedIndex,
              onTap: onTap,
              icons: icons,
              labels: labels,
              semanticsLabels: semanticsLabels,
              compactProgress: compactProgress,
            ),
          ],
        ),
      ),
    );
  }
}

class _PillItems extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final List<IconData> icons;
  final List<String?> labels;
  final List<String>? semanticsLabels;
  final double compactProgress;

  const _PillItems({
    required this.selectedIndex,
    required this.onTap,
    required this.icons,
    required this.labels,
    this.semanticsLabels,
    required this.compactProgress,
  });

  @override
  State<_PillItems> createState() => _PillItemsState();
}

class _PillItemsState extends State<_PillItems> {
  double? _dragIndex;

  void _updateDrag(DragUpdateDetails details, double width) {
    final count = widget.icons.length;
    if (count == 0 || width <= 0) return;

    final segment = width / count;
    final next =
        ((_dragIndex ?? widget.selectedIndex.toDouble()) +
                details.delta.dx / segment)
            .clamp(0.0, count - 1.0);

    setState(() => _dragIndex = next);
  }

  void _finishDrag() {
    final dragIndex = _dragIndex;
    if (dragIndex == null) return;
    final index = dragIndex.round().clamp(0, widget.icons.length - 1);
    setState(() => _dragIndex = null);
    if (index != widget.selectedIndex) {
      widget.onTap(index);
    }
  }

  @override
  void didUpdateWidget(covariant _PillItems oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex && _dragIndex == null) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.icons.length;
    if (count == 0) return const SizedBox.shrink();

    // Search lives in the persistent trailing circle. When Search is active,
    // keep Home as the compact left-side shortcut instead of duplicating Search.
    final compactIndex =
        widget.selectedIndex < count ? widget.selectedIndex : 0;
    final activeIndex = _dragIndex ?? widget.selectedIndex.toDouble();
    final compactProgress = widget.compactProgress;
    final primary = Theme.of(context).colorScheme.primary;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final compactColor = widget.selectedIndex == compactIndex
        ? primary
        : (isLight ? Colors.black : Colors.white);

    return LayoutBuilder(
      builder: (context, constraints) {
        final segment = constraints.maxWidth / count;
        final lensWidth = (segment - 10).clamp(0.0, segment).toDouble();
        final left = segment * activeIndex + 5;

        return SizedBox(
          height: FloatingPillNavBar.bodyHeight,
          child: Stack(
            children: [
              ExcludeSemantics(
                excluding: compactProgress >= 0.5,
                child: IgnorePointer(
                  ignoring: compactProgress >= 0.5,
                  child: Opacity(
                    opacity: 1.0 - compactProgress,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragUpdate: (details) =>
                          _updateDrag(details, constraints.maxWidth),
                      onHorizontalDragEnd: (_) => _finishDrag(),
                      child: SizedBox(
                        height: FloatingPillNavBar.bodyHeight,
                        child: Stack(
                          children: [
                            if (_dragIndex == null && compactProgress == 0.0)
                              AnimatedPositioned(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                left: left,
                                top: 4.5,
                                width: lensWidth,
                                height: 53,
                                child: IgnorePointer(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: AppColors.of(
                                        context,
                                      ).glassActiveLens,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ),
                                ),
                              )
                            else
                              Positioned(
                                left: left,
                                top: 4.5,
                                width: lensWidth,
                                height: 53,
                                child: IgnorePointer(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: AppColors.of(
                                        context,
                                      ).glassActiveLens,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ),
                                ),
                              ),
                            Row(
                              children: [
                                for (var i = 0; i < count; i++)
                                  Expanded(
                                    child: _PillItem(
                                      icon: widget.icons[i],
                                      iconSize: i == 2
                                          ? FloatingPillNavBar._iconSize + 2
                                          : FloatingPillNavBar._iconSize,
                                      label: widget.labels[i],
                                      semanticsLabel:
                                          widget.semanticsLabels != null
                                          ? widget.semanticsLabels![i]
                                          : widget.labels[i],
                                      active: i == widget.selectedIndex,
                                      onTap: () => widget.onTap(i),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (compactProgress > 0.0)
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: compactProgress < 0.5,
                    child: Opacity(
                      opacity: compactProgress,
                      child: Semantics(
                        button: true,
                        selected: widget.selectedIndex == compactIndex,
                        label: widget.labels[compactIndex],
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => widget.onTap(compactIndex),
                          child: Center(
                            child: Transform.scale(
                              scale: 0.84 + 0.16 * compactProgress,
                              child: Icon(
                                widget.icons[compactIndex],
                                size: compactIndex == 2
                                  ? FloatingPillNavBar._iconSize + 2
                                  : FloatingPillNavBar._iconSize,
                                color: compactColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PillItem extends StatelessWidget {
  final IconData icon;
  final double iconSize;
  final String? label;
  final String? semanticsLabel;
  final bool active;
  final VoidCallback onTap;

  const _PillItem({
    required this.icon,
    required this.iconSize,
    required this.label,
    required this.semanticsLabel,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final color = active ? primary : (isLight ? Colors.black : Colors.white);

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
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    FloatingPillNavBar._iconSize == 24 ? icon : icon,
                    size: iconSize,
                    color: color,
                  ),
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
                          fontWeight: active
                              ? FontWeight.w600
                              : FontWeight.w400,
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
    final primary = Theme.of(context).colorScheme.primary;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final inactiveColor = isLight ? Colors.black : Colors.white;
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
                    filterConfig: FloatingPillNavBar._pillBlurConfig,
                    blendMode: BlendMode.srcOver,
                    child: const ColoredBox(color: Colors.transparent),
                  ),
                ),
                ColoredBox(color: pillGlassSurfaceTint(context)),
                IgnorePointer(
                  child: CustomPaint(
                    painter: PillGlassRimPainter(
                      radius: FloatingPillNavBar.trailingSize / 2,
                      isDark: Theme.of(context).brightness == Brightness.dark,
                    ),
                  ),
                ),
                Center(
                  child: Icon(
                    icon,
                    size: FloatingPillNavBar._iconSize,
                    color: active ? primary : inactiveColor,
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

/// Draws a subtle specular glass reflection without a hairline contact outline.
class PillGlassRimPainter extends CustomPainter {
  const PillGlassRimPainter({
    required this.radius,
    required this.isDark,
  });

  final double radius;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final bounds = Offset.zero & size;

    // Keep the specular reflection without the hairline contact outline.
    final innerBounds = bounds.deflate(0.8);
    final innerRadius = (radius - 0.8).clamp(0.0, double.infinity).toDouble();
    final innerRRect = RRect.fromRectAndRadius(
      innerBounds,
      Radius.circular(innerRadius),
    );

    // Preserve the existing dark-mode reflection exactly. Light mode uses a
    // neutral gray rim so the edge remains visible without looking white.
    final colors = isDark
        ? const [
            Color(0x40FFFFFF),
            Color(0x0DFFFFFF),
            Color(0x0A000000),
            Color(0x0DFFFFFF),
            Color(0x26FFFFFF),
          ]
        : const [
            Color(0x263C3C43),
            Color(0x143C3C43),
            Color(0x0A3C3C43),
            Color(0x143C3C43),
            Color(0x263C3C43),
          ];

    canvas.drawRRect(
      innerRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, 0.14, 0.5, 0.86, 1],
          colors: colors,
        ).createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(covariant PillGlassRimPainter oldDelegate) =>
      radius != oldDelegate.radius || isDark != oldDelegate.isDark;
}
