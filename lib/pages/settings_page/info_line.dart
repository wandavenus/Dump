part of '../settings_page.dart';

// TODO(cleanup): _InfoLine duplicates SettingsInfoRow (settings_widgets/info.dart)
// in intent but differs in padding and font sizes (compact 12px vs full 16px).
// Consolidate once a shared compact-row variant exists in settings_widgets.
class _InfoLine extends StatelessWidget {
  final String label;
  final String val;
  const _InfoLine(this.label, this.val);

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text('$label: ',
              style: TextStyle(
                  color: c.secondaryLabel, fontSize: 12)),
          Expanded(
            child: Text(val,
                style: TextStyle(
                    color: c.primaryLabel.withValues(alpha: 0.70),
                    fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
