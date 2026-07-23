part of '../settings_widgets.dart';

class SettingsInfoRow extends StatelessWidget {
  final String title;
  final String trailing;

  const SettingsInfoRow({
    super.key,
    required this.title,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(color: c.primaryLabel, fontSize: 16),
            ),
          ),
          Text(
            trailing,
            style: TextStyle(color: c.secondaryLabel, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

// ─── Action Row ───────────────────────────────────────────────────────────────
