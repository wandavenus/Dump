part of '../settings_page.dart';

// ── Equalizer Section ──────────────────────────────────────────────────────────
//
// Entry point di Settings → membuka EqualizerPage (full-screen push navigation).
// EqualizerPage berisi:
//   • Preset chips EQ (Flat, Rock, Pop, Jazz, Classical, dll.)
//   • Vertical band sliders — jumlah band & frekuensi dari android.media.audiofx.Equalizer
//   • Reverb section — android.media.audiofx.PresetReverb (7 preset diskrit)

class _EqualizerSection extends StatelessWidget {
  const _EqualizerSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader('EQUALIZER'),
        const SizedBox(height: 6),
        ValueListenableBuilder<bool>(
          valueListenable: AudioEffectsService.equalizerEnabled,
          builder: (_, enabled, _) {
            return ValueListenableBuilder<int>(
              valueListenable: AudioEffectsService.eqPreset,
              builder: (_, presetIdx, _) {
                String trailing;
                if (!enabled) {
                  trailing = 'Nonaktif';
                } else if (presetIdx >= 0 &&
                    presetIdx < AudioEffectsService.eqPresets.length) {
                  trailing =
                      AudioEffectsService.eqPresets[presetIdx]['name'] as String;
                } else {
                  trailing = 'Custom';
                }
                return SettingsActionRow(
                  title: 'Equalizer',
                  trailing: trailing,
                  onTap: () => Navigator.of(context).push(
                    CupertinoPageRoute<void>(
                      builder: (_) => const EqualizerPage(),
                    ),
                  ),
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
