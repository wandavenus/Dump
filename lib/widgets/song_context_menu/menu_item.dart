part of '../song_context_menu.dart';

// ─── _MenuItem ────────────────────────────────────────────────────────────────
//
// Reusable tappable row for the context menu.  Private to this library so it
// can only be used within [SongContextMenu] — callers compose the menu by
// stacking [_MenuItem] instances separated by [_insetDivider].

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String label;
  final Color? labelColor;
  final VoidCallback? onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    this.onTap,
    this.iconColor,
    this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Icon(icon, color: iconColor ?? const Color(0xFFF92D48), size: 22),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                color: labelColor ?? c.primaryLabel,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
