part of '../../settings_page.dart';

// ── AutoMix ──────────────────────────────────────────────────────────────────
// A single on/off control. Detailed tuning stays internal so the Audio settings
// page uses the same compact row pattern as the other audio effects.
//
// The subtitle doubles as the pipeline status: AutoMix analyzes the upcoming
// tracks by itself, and while that runs the row reports progress so the user
// can see the feature working without a manual scan button.

class _AutomixSection extends StatelessWidget {
  const _AutomixSection();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return ValueListenableBuilder<bool>(
      valueListenable: AutomixService.automixEnabled,
      builder: (context, enabled, _) =>
          ValueListenableBuilder<AutomixAnalysisProgress>(
            valueListenable: AutomixService.analysisProgress,
            builder: (context, progress, _) => SettingsToggleRow(
              title: l.automixTitle,
              subtitle: enabled && progress.running
                  ? l.automixAnalyzingProgress(progress.done, progress.total)
                  : l.automixDescription,
              value: enabled,
              onChanged: AutomixService.setAutomixEnabled,
            ),
          ),
    );
  }
}
