part of '../song_context_menu.dart';

// ─── _InfoRow ─────────────────────────────────────────────────────────────────
//
// Label + value row used inside the "Informasi Lagu" AlertDialog.

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: TextStyle(color: c.secondaryLabel, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: c.primaryLabel, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
