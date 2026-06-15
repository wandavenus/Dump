part of '../settings_page.dart';

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color = const Color(0xFF8E8E93),
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? color : const Color(0xFF48484A), width: 0.5),
        ),
        child: Text(label, style: TextStyle(color: color, fontSize: 11)),
      ),
    );
  }
}

// ─── DEBUG ────────────────────────────────────────────────────────────────────
