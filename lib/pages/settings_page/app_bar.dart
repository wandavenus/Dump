part of '../settings_page.dart';

class _SettingsAppBar extends StatelessWidget implements PreferredSizeWidget {
  final double scrollOffset;

  const _SettingsAppBar({required this.scrollOffset});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 0.5);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ThemeController.glassTheme,
      builder: (context, isGlass, _) {
        return AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: isGlass ? Colors.transparent : Colors.black,
          surfaceTintColor: Colors.transparent,
          flexibleSpace: isGlass
              ? RepaintBoundary(
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                      child: Container(
                        color: Colors.white.withValues(alpha: 0.055),
                      ),
                    ),
                  ),
                )
              : null,
          title: Transform.translate(
            offset: Offset(
              0,
              (1 - (scrollOffset / 100).clamp(0.0, 1.0)) * 40,
            ),
            child: Opacity(
              opacity: (((scrollOffset - 25) / 25).clamp(0.0, 1.0) * 1.5)
                  .clamp(0.0, 1.0),
              child: const Text(
                'Pengaturan',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          centerTitle: false,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(0.5),
            child: isGlass
                ? Container(
                    height: 0.5,
                    color: Colors.white.withValues(alpha: 0.18),
                  )
                : Opacity(
                    opacity: (scrollOffset / 140).clamp(0.0, 1.0),
                    child: Container(
                      height: 0.9,
                      color: const Color(0xFF48484A),
                    ),
                  ),
          ),
        );
      },
    );
  }
}

// ─── Body ─────────────────────────────────────────────────────────────────────
