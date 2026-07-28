part of '../../settings_page.dart';

class _CrossfeedSection extends StatelessWidget {
  const _CrossfeedSection();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return ValueListenableBuilder<bool>(
      valueListenable: AudioEffectsService.crossfeedEnabled,
      builder: (context, enabled, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsToggleRow(
              title: l.crossfeedTitle,
              subtitle: enabled
                  ? l.crossfeedActiveSubtitle
                  : l.crossfeedInactiveSubtitle,
              value: enabled,
              onChanged: AudioEffectsService.setCrossfeedEnabled,
            ),
            if (enabled) ...[
              const SizedBox(height: 2),
              ValueListenableBuilder<double>(
                valueListenable: AudioEffectsService.crossfeedAmount,
                builder: (_, amount, _) => SettingsSliderRow(
                  title: l.crossfeedStrength,
                  subtitle: '${(amount * 100).round()}%',
                  value: amount,
                  min: 0.0,
                  max: 1.0,
                  onChanged: AudioEffectsService.setCrossfeedAmount,
                  divisions: 20,
                  showReset: amount != 0.3,
                  onReset: () => AudioEffectsService.setCrossfeedAmount(0.3),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
