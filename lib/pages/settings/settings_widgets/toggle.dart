part of '../settings_widgets.dart';

class SettingsToggleRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final Future<void> Function(bool) onChanged;

  const SettingsToggleRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: c.primaryLabel, fontSize: 16),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(color: c.secondaryLabel, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          CupertinoSwitch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: const Color(0xFFF92D48),
          ),
        ],
      ),
    );
  }
}

// ─── Slider Row ───────────────────────────────────────────────────────────────
