part of '../settings_page.dart';

class _AudioOutputSection extends StatelessWidget {
  const _AudioOutputSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader('JALUR AUDIO'),
        const SizedBox(height: 6),
        ValueListenableBuilder<int>(
          valueListenable: AudioEffectsService.audioOutputMode,
          builder: (_, mode, _) => _AudioOutputRow(mode: mode),
        ),
        const SettingsDivider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ValueListenableBuilder<int>(
            valueListenable: AudioEffectsService.audioOutputMode,
            builder: (_, mode, _) => Text(
              AudioEffectsService.audioOutputDesc[mode.clamp(0, 2).toInt()],
              style: const TextStyle(color: Color(0xFF636366), fontSize: 12),
            ),
          ),
        ),
        const SettingsDivider(),
        ValueListenableBuilder<bool>(
          valueListenable: AudioEffectsService.offloadSchedulingEnabled,
          builder: (_, enabled, _) => SettingsToggleRow(
            title: 'Audio Offload Scheduling',
            subtitle: 'Preferensi disimpan — Media3 1.10.1 mengelola scheduling secara internal; '
                'pengaturan ini tidak berpengaruh hingga versi Media3 berikutnya.',
            value: enabled,
            onChanged: AudioEffectsService.setOffloadSchedulingEnabled,
          ),
        ),
      ],
    );
  }
}
