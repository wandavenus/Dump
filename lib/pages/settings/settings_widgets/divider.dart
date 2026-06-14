part of '../settings_widgets.dart';

class SettingsDivider extends StatelessWidget {
  final double indent;
  const SettingsDivider({super.key, this.indent = 16});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 0.5,
      thickness: 0.5,
      color: const Color(0xFF38383A),
      indent: indent,
      endIndent: 0,
    );
  }
}

// ─── Toggle Row ───────────────────────────────────────────────────────────────
