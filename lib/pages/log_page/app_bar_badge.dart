part of '../log_page.dart';

// ─── _AppBarBadge ─────────────────────────────────────────────────────────────
//
// Small pill badge shown in the [LogPage] AppBar title to surface the current
// error and warning counts at a glance without opening the filter row.

class _AppBarBadge extends StatelessWidget {
  const _AppBarBadge({required this.count, required this.color});
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      '$count',
      style: TextStyle(
        color: color.withValues(alpha: 0.85),
        fontSize: 10,
        fontFamily: 'monospace',
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
