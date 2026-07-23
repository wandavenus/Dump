part of '../settings_widgets.dart';

class SettingsSectionHeader extends StatelessWidget {
  final String text;
  const SettingsSectionHeader(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: Color(0xFFF92D48),
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ─── Divider ──────────────────────────────────────────────────────────────────
