part of '../scrolling_page_chrome.dart';

class FadingTitleAppBar extends StatelessWidget implements PreferredSizeWidget {
  const FadingTitleAppBar({
    super.key,
    this.title,
    this.scrollOffset = 0,
    this.scrollOffsetListenable,
    this.leading,
    this.actions = const [CommonActions()],
    this.automaticallyImplyLeading = false,
  });

  final String? title;

  /// Static fallback used when [scrollOffsetListenable] is null.
  /// Pass a fixed value (e.g. 100) for pages with no scrollable title.
  final double scrollOffset;

  /// When provided, only the title/divider elements rebuild on scroll —
  /// not the entire Scaffold. Preferred over mutating [scrollOffset] via
  /// setState to avoid full-page rebuilds on every scroll event.
  final ValueNotifier<double>? scrollOffsetListenable;

  final Widget? leading;
  final List<Widget>? actions;
  final bool automaticallyImplyLeading;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 0.5);

  @override
  Widget build(BuildContext context) {
    final notifier = scrollOffsetListenable;
    if (notifier != null) {
      return ValueListenableBuilder<double>(
        valueListenable: notifier,
        builder: (context, offset, _) => _buildBar(context, offset),
      );
    }
    return _buildBar(context, scrollOffset);
  }

  Widget _buildBar(BuildContext context, double offset) {
    final c = AppColors.of(context);
    final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;
    return AppBar(
      automaticallyImplyLeading: automaticallyImplyLeading,
      leading: leading,
      backgroundColor: scaffoldBg,
      surfaceTintColor: Colors.transparent,
      flexibleSpace: null,
      title: title != null
          ? Transform.translate(
              offset: Offset(
                0,
                (1 - ((offset - 30) / 40).clamp(0.0, 1.0).toDouble()) * 40,
              ),
              child: Text(
                title!,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w400,
                ),
              ),
            )
          : null,
      centerTitle: false,
      actions: actions,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(0.5),
        child: Opacity(
          opacity: (offset / 140).clamp(0.0, 1.0).toDouble(),
          child: Container(height: 0.9, color: c.separator),
        ),
      ),
    );
  }
}
