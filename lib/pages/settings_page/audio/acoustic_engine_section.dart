part of '../../settings_page.dart';

class _AcousticEngineSection extends StatelessWidget {
  const _AcousticEngineSection();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AudioEffectsService.acousticEngineEnabled,
      builder: (context, enabled, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsToggleRow(
            title: 'Acoustic Engine',
            subtitle: enabled
                ? 'Speaker enhancement is active'
                : 'Enhance built-in speaker playback',
            value: enabled,
            onChanged: AudioEffectsService.setAcousticEngineEnabled,
          ),
          if (enabled)
            ValueListenableBuilder<double>(
              valueListenable: AudioEffectsService.acousticEngineIntensity,
              builder: (context, intensity, _) => SettingsSliderRow(
                title: 'Intensity',
                subtitle: '${intensity.round()}%',
                value: intensity,
                min: 0,
                max: 100,
                divisions: 20,
                onChanged: (value) => unawaited(
                  AudioEffectsService.setAcousticEngineIntensity(value),
                ),
                expandable: true,
              ),
            ),
        ],
      ),
    );
  }
}
