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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
          Text(
            trailing,
            style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 15),
          ),
        ],
      ),
    );
  }
}

// ─── Action Row ───────────────────────────────────────────────────────────────
