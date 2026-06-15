part of '../scrolling_page_chrome.dart';

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
              ? ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                    child: Container(
                      color: Colors.white.withValues(alpha: 0.055),
                    ),
                  ),
                )
              : null,
          title: Transform.translate(
            offset: Offset(0, (1 - (scrollOffset / 100).clamp(0.0, 1.0).toDouble()) * 40),
            child: Opacity(
              opacity: ((((scrollOffset - 25) / 25).clamp(0.0, 1.0).toDouble()) * 1.5)
                  .clamp(0.0, 1.0)
                  .toDouble(),
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
            child: isGlass
                ? Container(
                    height: 0.5,
                    color: Colors.white.withValues(alpha: 0.18),
                  )
                : Opacity(
                    opacity: (scrollOffset / 140).clamp(0.0, 1.0).toDouble(),
                    child: Container(
                        height: 0.9, color: const Color(0xFF48484A)),
                  ),
          ),
        );
      },
    );
  }
}
