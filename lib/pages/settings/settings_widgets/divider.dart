part of '../settings_widgets.dart';

class SettingsDivider extends StatelessWidget {
  final double indent;
  final double endIndent;
  const SettingsDivider({super.key, this.indent = 16, this.endIndent = 16});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 0.5,
      thickness: 0.5,
      color: AppColors.of(context).separator,
      indent: indent,
      endIndent: endIndent,
    );
  }
}

// ─── Toggle Row ───────────────────────────────────────────────────────────────
