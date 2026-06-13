import 'dart:ui';
import 'package:flutter/material.dart';

import '../../themes/liquid_glass.dart';
import '../../themes/theme_controller.dart';
import '../common_actions.dart';

/// AppBar dengan judul yang muncul saat scroll, glass-aware.
class FadingTitleAppBar extends StatelessWidget implements PreferredSizeWidget {
  const FadingTitleAppBar({
    super.key,
    required this.title,
    required this.scrollOffset,
  });

  final String title;
  final double scrollOffset;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 0.5);

  Widget _solidBar(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: Colors.black,
      surfaceTintColor: Colors.transparent,
      title: Transform.translate(
        offset: Offset(0, (1 - (scrollOffset / 100).clamp(0.0, 1.0)) * 40),
        child: Opacity(
          opacity:
              ((((scrollOffset - 25) / 25).clamp(0.0, 1.0)) * 1.5).clamp(0.0, 1.0),
          child: Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      centerTitle: false,
      actions: const [CommonActions()],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(0.5),
        child: Opacity(
          opacity: (scrollOffset / 140).clamp(0.0, 1.0),
          child: Container(height: 0.9, color: const Color(0xFF48484A)),
        ),
      ),
    );
  }

  Widget _glassBar(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      flexibleSpace: const LiquidGlassBar(
        showBottomBorder: true,
        showTopBorder: false,
      ),
      title: Transform.translate(
        offset: Offset(0, (1 - (scrollOffset / 100).clamp(0.0, 1.0)) * 40),
        child: Opacity(
          opacity:
              ((((scrollOffset - 25) / 25).clamp(0.0, 1.0)) * 1.5).clamp(0.0, 1.0),
          child: Text(
            title,
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white),
          ),
        ),
      ),
      centerTitle: false,
      actions: const [CommonActions()],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(0.5),
        child: Opacity(
          opacity: (scrollOffset / 140).clamp(0.0, 1.0),
          child: Container(
              height: 0.5,
              color: Colors.white.withOpacity(0.18)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isGlass = ThemeController.isAppBarGlass;
    return isGlass ? _glassBar(context) : _solidBar(context);
  }
}

// ─── Library AppBar glass-aware ─────────────────────────────────────────────

/// AppBar standar (tanpa fading title) yang glass-aware — dipakai di LibraryPage.
class LibraryGlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const LibraryGlassAppBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 0.5);

  @override
  Widget build(BuildContext context) {
    final isGlass = ThemeController.isAppBarGlass;
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: isGlass ? Colors.transparent : Colors.black,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      flexibleSpace: isGlass
          ? const LiquidGlassBar(showBottomBorder: true)
          : null,
      title: const SizedBox.shrink(),
      centerTitle: false,
      actions: const [CommonActions()],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(0.5),
        child: Container(
          height: 0.9,
          color: isGlass
              ? Colors.white.withOpacity(0.12)
              : Colors.transparent,
        ),
      ),
    );
  }
}

/// AppBar untuk MusicList (Unduhan) yang glass-aware.
class DownloadsGlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const DownloadsGlassAppBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 1);

  @override
  Widget build(BuildContext context) {
    final isGlass = ThemeController.isAppBarGlass;
    return AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: 16,
      backgroundColor: isGlass ? Colors.transparent : null,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      flexibleSpace: isGlass ? const LiquidGlassBar(showBottomBorder: true) : null,
      title: const Text(
        'Unduhan',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
      ),
      actions: const [CommonActions()],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          color: isGlass
              ? Colors.white.withOpacity(0.12)
              : Colors.white24,
        ),
      ),
    );
  }
}

// ─── Komponen halaman umum ───────────────────────────────────────────────────

class LargePageTitle extends StatelessWidget {
  const LargePageTitle({super.key, required this.title, this.align = true});

  final String title;
  final bool align;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      title,
      style: const TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: align ? Align(alignment: Alignment.centerLeft, child: text) : text,
    );
  }
}

class HeaderDivider extends StatelessWidget {
  const HeaderDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Divider(color: Color(0xFF48484A), thickness: 0.5, height: 0),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.title,
    this.routeName,
    this.topMargin = 20,
    this.horizontalPadding = 15,
    this.showChevron = true,
  });

  final String title;
  final String? routeName;
  final double topMargin;
  final double horizontalPadding;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        Text(title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        if (showChevron)
          const Icon(Icons.chevron_right_rounded,
              color: Color.fromARGB(255, 186, 186, 186)),
      ],
    );

    return Container(
      margin: EdgeInsets.only(top: topMargin),
      height: 30,
      padding: EdgeInsets.only(left: horizontalPadding),
      child: routeName == null
          ? row
          : InkWell(
              onTap: () => Navigator.pushNamed(context, routeName!),
              child: row,
            ),
    );
  }
}
