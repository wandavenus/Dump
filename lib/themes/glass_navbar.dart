import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:musicplayer/theme/app_colors.dart';
import 'package:musicplayer/themes/app_theme_extension.dart';
import 'package:musicplayer/themes/theme_controller.dart';

/// Tinggi mini player (mode mini) — dipakai clearance konten scroll dan
/// geometri mini player di `unified_morph_player.dart`.
const double kMiniPlayerHeight = 64.5;

/// Ruang kosong di bawah konten scroll agar item terakhir tidak tertutup
/// mini player. Clearance menghitung sampai TOP mini player (bukan
/// bottom-nya — mini player setinggi [kMiniPlayerHeight]):
///
/// - Mode non-pill: mini player beristirahat di navBarH (53.8 glass /
///   55.1 solid) + inset layar, jadi clearance = navBarH + miniH + 10.7.
/// - Mode pill (iOS 26): mini player mengambang sebagai kapsul di atas
///   navbar (body 62 + gap 10 + miniPlayerGap 10 + inset), jadi clearance
///   = body + gap + miniPlayerGap + miniH + 10.7.
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
  // Strip glass menghilangkan separator 1.5px di atas bar (70 vs 71.5),
  // jadi navBarH turun 1.5px — konsisten dengan _buildMorph di
  // unified_morph_player.dart.
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
        // RepaintBoundary isolates the BackdropFilter so it is not
        // recomposited when navigation items or overlying widgets change.
        Positioned.fill(
          child: RepaintBoundary(
            child: ClipRect(
              child: BackdropFilter(
                // Keep the backdrop radius modest: this filter is recomputed
                // while content scrolls behind the navbar. A large sigma is
                // disproportionately expensive on the target Snapdragon 730.
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                blendMode: BlendMode.srcOver,
                // Transparan murni — hanya blur backdrop, tanpa tint, agar
                // konsisten dengan pill navbar & mini player pill.
                child: const ColoredBox(color: Colors.transparent),
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
/// Kapsul utama berisi item navigasi dengan blob apung di belakang ikon tab
/// aktif, dan opsional sebuah tombol bundar terpisah (trailing, mis. ikon
/// Search) yang mengambang di sebelah kanan dengan material glass yang sama.
class FloatingPillNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final List<IconData> icons;

  /// Label visual per item; `null` = tanpa label.
  final List<String?> labels;

  /// Label untuk screen reader — harus selalu lengkap walau label visual `null`.
  final List<String>? semanticsLabels;

  /// Ikon tombol trailing terpisah (mis. Search). Indeksnya = [icons.length].
  final IconData? trailingIcon;

  /// Nama tombol trailing untuk screen reader.
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

  /// Tinggi badan kapsul (area ikon + label).
  static const double bodyHeight = 62.0;

  /// Margin kiri/kanan dari tepi layar.
  static const double horizMargin = 14.0;

  /// Jarak apung dari tepi bawah layar (di atas home indicator).
  static const double bottomGap = 10.0;

  /// Jarak vertikal antara mini player (mode pill) dan tepi atas kapsul
  /// navbar — mini player mengambang, tidak menempel ke navbar.
  static const double miniPlayerGap = 10.0;

  /// Jarak antara kapsul utama dan tombol bundar terpisah.
  static const double trailingGap = 10.0;

  /// Diameter tombol bundar terpisah — disamakan dengan tinggi kapsul agar
  /// konsisten dengan pill 4 tab (tepi atas/bawah sejajar).
  static const double trailingSize = bodyHeight;

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
    );
  }

  Widget _buildCapsule(
    BuildContext context,
    AppThemeExtension c,
    double radius,
  ) {
    // Ukuran eksplisit WAJIB: Stack berisi hanya Positioned.fill (tanpa child
    // non-positioned), jadi RenderStack mengembalikan constraints.biggest.
    // Tanpa SizedBox ini kapsul meledak ke seluruh tinggi layar dan menutupi
    // seluruh app (tidak bisa disentuh + navbar hilang).
    return SizedBox(
      width: double.infinity,
      height: FloatingPillNavBar.bodyHeight,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        // Kapsul transparan murni: blur backdrop + border hairline saja.
        // Tanpa tint dan tanpa saturasi supaya warna pill sama persis dengan
        // warna background di belakangnya — konsisten dengan mini player pill.
        child: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: const ColoredBox(color: Colors.transparent),
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
                    border: Border.all(
                      color: c.glassBorderTint,
                      width: 1,
                    ),
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
    final primary = Theme.of(context).colorScheme.primary;
    final count = icons.length;
    return SizedBox(
      height: FloatingPillNavBar.bodyHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemW = constraints.maxWidth / count;
          final blobW = itemW - FloatingPillNavBar._blobInset * 2;
          // Posisi vertikal blob mengikuti pusat ikon: item berlabel punya
          // area label di bawah, item tanpa label terpusat penuh.
          final hasLabel =
              selectedIndex < labels.length && labels[selectedIndex] != null;
          final blobTop = hasLabel
              ? (FloatingPillNavBar.bodyHeight -
                        FloatingPillNavBar._labelHeight -
                        FloatingPillNavBar._blobHeight) /
                    2
              : (FloatingPillNavBar.bodyHeight -
                        FloatingPillNavBar._blobHeight) /
                    2;
          // Saat tab trailing (Search) aktif, blob memudar di slot terakhir.
          final blobSlot = selectedIndex < count ? selectedIndex : count - 1;
          return Stack(
            children: [
              // Blob apung di belakang ikon tab aktif — meluncur antar tab.
              AnimatedOpacity(
                opacity: selectedIndex < count ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: AnimatedPositioned(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  left: blobSlot * itemW + FloatingPillNavBar._blobInset,
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
            if (label != null) ...[
              const SizedBox(height: 3),
              // Auto-shrink label agar kata panjang (mis. "Perpustakaan") tetap
              // utuh dan tidak terpotong/ellipsis di slot sempit.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label!,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Tombol bundar terpisah (mis. ikon Search) dengan material glass yang sama
/// dengan kapsul utama. Saat aktif, terisi fill blob dan ikon menyala.
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
          // Sama seperti kapsul: transparan murni (blur backdrop + border).
          // SizedBox eksplisit juga wajib di sini — Stack tanpa ukuran
          // mengembalikan constraints.biggest dan tombol meledak ke layar
          // penuh (regresi yang sama dengan kapsul).
          child: SizedBox(
            width: FloatingPillNavBar.trailingSize,
            height: FloatingPillNavBar.trailingSize,
            child: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: const ColoredBox(color: Colors.transparent),
                    ),
                  ),
                ),
                // Fill aktif — membulat penuh.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active
                        ? primary.withValues(alpha: 0.15)
                        : Colors.transparent,
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: c.glassBorderTint,
                      width: 1,
                    ),
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