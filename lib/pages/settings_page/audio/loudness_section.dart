part of '../../settings_page.dart';

class _LoudnessNormSection extends StatelessWidget {
  const _LoudnessNormSection();

  static const _lufsTargets = <double>[-14.0, -16.0, -18.0, -23.0];
  static const _lufsLabels  = ['-14 LUFS', '-16 LUFS', '-18 LUFS', '-23 LUFS'];

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return ValueListenableBuilder<bool>(
      valueListenable: AudioEffectsService.loudnessNormEnabled,
      builder: (context, enabled, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsToggleRow(
              title:    l.loudnessNormalization,
              subtitle: enabled
                  ? l.loudnessNormActiveSubtitle
                  : l.loudnessNormInactiveSubtitle,
              value:     enabled,
              onChanged: AudioEffectsService.setLoudnessNormEnabled,
            ),
            if (enabled) ...[
              const SizedBox(height: 2),
              ValueListenableBuilder<double>(
                valueListenable: AudioEffectsService.loudnessNormTarget,
                builder: (context, target, _) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.loudnessTarget(target.toStringAsFixed(1)),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 6),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: List.generate(_lufsTargets.length, (i) {
                              final selected = (target - _lufsTargets[i]).abs() < 0.1;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(_lufsLabels[i]),
                                  selected: selected,
                                  onSelected: (_) {
                                    unawaited(AudioEffectsService.setLoudnessNormTarget(_lufsTargets[i]));
                                  },
                                ),
                              );
                            }),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l.loudnessHint,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(160),
                              ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ],
        );
      },
    );
  }
}
