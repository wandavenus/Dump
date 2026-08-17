import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:musicplayer/theme/app_colors.dart';
import 'package:musicplayer/themes/theme_controller.dart';

/// Ruang kosong di bawah konten scroll agar item terakhir tidak tertutup
/// mini player. Mode non-pill: mini player beristirahat di navBarH (53.8) +
/// inset layar, clearance 64.5 memberi buffer ~10.7 px. Mode pill (iOS 26):
/// mini player duduk tepat di atas tepi atas kapsul (body 62 + gap 10 +
/// inset), jadi clearance naik dengan buffer yang sama.
double navBottomClearance(BuildContext context) {
  final safeBottom = MediaQuery.paddingOf(context).bottom;
  if (ThemeController.isPillNavBar) {
    return FloatingPillNavBar.bodyHeight +
        FloatingPillNavBar.bottomGap +
        safeBottom +
        10.7;
  }
  return 64.5 + safeBottom;
}

class GlassNavBar extends StatelessWidget {
  final Widget child;

  const GlassNavBar({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Stack(
      children: [
        // RepaintBoundary isolates the BackdropFilter so it is not
        // recomposited when navigation items or overlying widgets change.
        Positioned.fill(
          child: RepaintBoundary(
            child: ClipRect(
              child: BackdropFilter(
                // Keep the backdrop radius modest: this filter is recomputed
                // while content scrolls behind the navbar. A large sigma is
                // disproportionately expensive on the target Snapdragon 730.
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                blendMode: BlendMode.srcOver,
                child: Container(color: c.glassNavTint),
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 0.5,
          child: Container(color: c.glassBorderTint),
        ),
        child,
      ],
    );
  }
}

/// Navbar kapsul apung gaya iOS 26 (Liquid Glass).
///
/// Berbeda dari [GlassNavBar] (strip penuh selebar layar), kapsul ini
/// mengambang dengan margin kiri/kanan/bawah, berbentuk kapsul penuh, blur +
/// saturasi kaca cair, dan blob apung yang meluncur di belakang ikon tab
/// aktif. Item dengan label `null` (mis. ikon Search) tidak menampilkan label.
class FloatingPillNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final List<IconData> icons;

  /// Label visual per item; `null` = tanpa label (mis. ikon Search).
  final List<String?> labels;

  /// Label untuk screen reader — harus selalu lengkap walau label visual `null`.
  final List<String>? semanticsLabels;

  const FloatingPillNavBar({
    super.key,
    required this.selectedIndex,
    required this.onTap,
    required this.icons,
    required this.labels,
    this.semanticsLabels,
  });

  /// Tinggi badan kapsul (area ikon + label).
  static const double bodyHeight = 62.0;

  /// Margin kiri/kanan dari tepi layar.
  static const double horizMargin = 14.0;

  /// Jarak apung dari tepi bawah layar (di atas home indicator).
  static const double bottomGap = 10.0;

  static const double _blobHeight = 38.0;
  static const double _blobInset = 5.0;
  static const double _labelHeight = 14.0;
  static const double _iconSize = 24.0;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final radius = bodyHeight / 2;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizMargin,
        0,
        horizMargin,
        bottomGap + safeBottom,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: ColorFiltered(
          // Saturasi ringan — ciri khas Liquid Glass iOS 26.
          colorFilter: ColorFilter.matrix(_saturationMatrix(1.5)),
          child: Stack(
            children: [
              // Backdrop blur diisolasi dalam RepaintBoundary agar tidak
              // recomposite saat item tab berubah.
              Positioned.fill(
                child: RepaintBoundary(
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                      child: const ColoredBox(color: Colors.transparent),
                    ),
                  ),
                ),
              ),
              // Tint kaca.
              Positioned.fill(child: ColoredBox(color: c.glassNavTint)),
              // Highlight specular di tepi atas — kesan "kaca cair".
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 28,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.10),
                          Colors.white.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Border kaca tipis.
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(radius),
                      border: Border.all(color: c.glassBorderTint, width: 1),
                    ),
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

  /// Matriks saturasi (luminance-weighted) untuk efek Liquid Glass.
  static List<double> _saturationMatrix(double s) {
    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    final sr = (1 - s) * lr, sg = (1 - s) * lg, sb = (1 - s) * lb;
    return [
      sr + s, sg, sb, 0, 0, //
      sr, sg + s, sb, 0, 0, //
      sr, sg, sb + s, 0, 0, //
      0, 0, 0, 1, 0,
    ];
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
    final primary = Theme.of(context).colorScheme.primary;
    final count = icons.length;
    return SizedBox(
      height: FloatingPillNavBar.bodyHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemW = constraints.maxWidth / count;
          final blobW = itemW - FloatingPillNavBar._blobInset * 2;
          // Posisi vertikal blob mengikuti pusat ikon: item berlabel punya
          // area label di bawah, item tanpa label (Search) terpusat penuh.
          final hasLabel = labels[selectedIndex] != null;
          final blobTop = hasLabel
              ? (FloatingPillNavBar.bodyHeight -
                      FloatingPillNavBar._labelHeight -
                      FloatingPillNavBar._blobHeight) /
                  2
              : (FloatingPillNavBar.bodyHeight -
                      FloatingPillNavBar._blobHeight) /
                  2;
          return Stack(
            children: [
              // Blob apung di belakang ikon tab aktif — meluncur antar tab.
              AnimatedPositioned(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                left: selectedIndex * itemW + FloatingPillNavBar._blobInset,
                top: blobTop,
                width: blobW,
                height: FloatingPillNavBar._blobHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(
                      FloatingPillNavBar._blobHeight / 2,
                    ),
                  ),
                ),
              ),
              Row(
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
            ],
          );
        },
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: FloatingPillNavBar._iconSize, color: color),
            if (label != null) ...[const SizedBox(height: 3), Text(
                  label!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight:
                        active ? FontWeight.w600 : FontWeight.w400,
                  ),
                )],
          ],
        ),
      ),
    );
  }
}
