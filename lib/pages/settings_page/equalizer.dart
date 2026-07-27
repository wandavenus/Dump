part of '../settings_page.dart';

class _EqualizerSection extends StatelessWidget {
  const _EqualizerSection();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionHeader(l.sectionEqualizer),
        const SizedBox(height: 6),
        ValueListenableBuilder<bool>(
          valueListenable: AudioEffectsService.bitPerfectMode,
          builder: (_, bitPerfect, _) {
            return ValueListenableBuilder<bool>(
              valueListenable: AudioEffectsService.equalizerEnabled,
              builder: (_, enabled, _) {
                return ValueListenableBuilder<int>(
                  valueListenable: AudioEffectsService.eqPreset,
                  builder: (_, presetIdx, _) {
                    String trailing;
                    if (bitPerfect) {
                      trailing = l.equalizerBitPerfect;
                    } else if (!enabled) {
                      trailing = l.disabled;
                    } else if (presetIdx >= 0 &&
                        presetIdx < AudioEffectsService.eqPresets.length) {
                      trailing = AudioEffectsService.eqPresets[presetIdx]['name'] as String;
                    } else {
                      trailing = l.equalizerCustom;
                    }
                    return SettingsActionRow(
                      title: l.equalizerTitle,
                      subtitle: trailing,
                      onTap: () => Navigator.of(context).push(
                        ZoomFadeRoute<void>(page: const EqualizerPage()),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
        const SettingsDivider(),
      ],
    );
  }
}
