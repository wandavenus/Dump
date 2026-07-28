part of '../settings_page.dart';

// TODO(cleanup): _GlassSubToggle duplicates SettingsToggleRow conceptually but
// differs in padding, icon, and onChanged signature (Future<void> vs ValueChanged).
// Consolidate once the glass-theme API is stabilised.
class _GlassSubToggle extends StatelessWidget {
  final String label;
  final ValueNotifier<bool> notifier;
  final Future<void> Function(bool) onChanged;

  const _GlassSubToggle({
    required this.label,
    required this.notifier,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: notifier,
      builder: (_, value, _) => Padding(
        padding: const EdgeInsets.only(
          left: 36,
          right: 16,
          top: 10,
          bottom: 10,
        ),
        child: Row(
          children: [
            Icon(Icons.blur_on, size: 16, color: c.secondaryLabel),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: c.primaryLabel, fontSize: 15),
              ),
            ),
            CupertinoSwitch(
              value: value,
              onChanged: onChanged,
              activeTrackColor: const Color(0xFFF92D48),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── AUDIO ────────────────────────────────────────────────────────────────────
