part of '../log_page.dart';

// ─── _BarBtn ──────────────────────────────────────────────────────────────────
//
// Compact icon + label button used in the [LogPage] bottom action bar.
// [destructive] tints the foreground red; [enabled] greys it out.

class _BarBtn extends StatelessWidget {
  const _BarBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.enabled     = true,
  });

  final IconData icon;
  final String   label;
  final VoidCallback onTap;
  final bool     destructive;
  final bool     enabled;

  @override
  Widget build(BuildContext context) {
    final Color fg = !enabled
        ? const Color(0xFF2C2C2E)
        : destructive
            ? const Color(0xFFF92D48)
            : const Color(0xFF8E8E93);

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color:        const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color:      fg,
                fontSize:   11,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
