part of '../settings_page.dart';

class _AudioSection extends StatelessWidget {
  const _AudioSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader('AUDIO'),
        const SizedBox(height: 6),

        // Normalize
        ValueListenableBuilder<bool>(
          valueListenable: AudioEffectsService.audioNormalize,
          builder: (_, v, __) => SettingsToggleRow(
            title: 'Audio Normalize',
            subtitle: 'Samakan volume semua lagu (AndroidLoudnessEnhancer)',
            value: v,
            onChanged: AudioEffectsService.setNormalize,
          ),
        ),
        const SettingsDivider(),

        // Crossfade
        ValueListenableBuilder<double>(
          valueListenable: AudioEffectsService.crossfadeDuration,
          builder: (_, v, __) => SettingsSliderRow(
            title: 'Crossfade',
            subtitle: v == 0 ? 'Nonaktif' : '${v.toStringAsFixed(1)} detik',
            value: v,
            min: 0,
            max: 12,
            onChanged: AudioEffectsService.setCrossfade,
            divisions: 24,
          ),
        ),
        const SettingsDivider(),

        ValueListenableBuilder<double>(
          valueListenable: AudioEffectsService.playbackSpeed,
          builder: (_, v, __) => SettingsSliderRow(
            title: 'Kecepatan Putar',
            subtitle: '${v.toStringAsFixed(2)}x',
            value: v,
            min: 0.25,
            max: 3.0,
            onChanged: AudioEffectsService.setSpeed,
            divisions: 22,
            showReset: v != 1.0,
            onReset: () => AudioEffectsService.setSpeed(1.0),
          ),
        ),
        const SettingsDivider(),

        ValueListenableBuilder<double>(
          valueListenable: AudioEffectsService.pitchShift,
          builder: (_, v, __) => SettingsSliderRow(
            title: 'Pitch Shift',
            subtitle: v == 0
                ? 'Normal'
                : '${v > 0 ? '+' : ''}${v.toStringAsFixed(1)} semitone',
            value: v,
            min: -6,
            max: 6,
            onChanged: AudioEffectsService.setPitch,
            divisions: 24,
            showReset: v != 0,
            onReset: () => AudioEffectsService.setPitch(0),
          ),
        ),
        const SettingsDivider(),

        ValueListenableBuilder<int>(
          valueListenable: AudioEffectsService.bassBoost,
          builder: (_, v, __) => SettingsSliderRow(
            title: 'Bass Boost',
            subtitle: v == 0
                ? 'Nonaktif'
                : AudioEngine.bassBoostSupported
                    ? '${(v / 10).round()}%'
                    : 'Tidak didukung perangkat ini',
            value: v.toDouble(),
            min: 0,
            max: 1000,
            onChanged: (val) => AudioEffectsService.setBassBoost(val.round()),
            divisions: 20,
            showReset: v != 0,
            onReset: () => AudioEffectsService.setBassBoost(0),
          ),
        ),
        const SettingsDivider(),

        ValueListenableBuilder<int>(
          valueListenable: AudioEffectsService.reverbPreset,
          builder: (_, v, __) => _ReverbRow(preset: v),
        ),
        const SettingsDivider(),
      ],
    );
  }
}