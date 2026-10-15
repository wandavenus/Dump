part of '../../settings_page.dart';

// ── AutoMix ──────────────────────────────────────────────────────────────────
// A single on/off control. Detailed tuning stays internal so the Audio settings
// page uses the same compact row pattern as the other audio effects.

class _AutomixSection extends StatelessWidget {
  const _AutomixSection();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return ValueListenableBuilder<bool>(
      valueListenable: AutomixService.automixEnabled,
      builder: (context, enabled, _) => SettingsToggleRow(
        title: l.automixTitle,
        subtitle: l.automixDescription,
        value: enabled,
        onChanged: AutomixService.setAutomixEnabled,
      ),
    );
  }
}
