part of 'settings_widgets.dart';

// ─── Info Row ─────────────────────────────────────────────────────────────────

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

class SettingsActionRow extends StatelessWidget {
  final String title;
  final String trailing;
  final VoidCallback onTap;
  final bool isDestructive;

  const SettingsActionRow({
    super.key,
    required this.title,
    required this.trailing,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: isDestructive ? const Color(0xFFF92D48) : Colors.white,
                  fontSize: 16,
                ),
              ),
            ),
            Text(
              trailing,
              style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 15),
            ),
            if (trailing.isNotEmpty) const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: Color(0xFF48484A), size: 20),
          ],
        ),
      ),
    );
  }
}
