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
          builder: (_, mode, __) => _AudioOutputRow(mode: mode),
        ),
        const SettingsDivider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ValueListenableBuilder<int>(
            valueListenable: AudioEffectsService.audioOutputMode,
            builder: (_, mode, __) => Text(
              AudioEffectsService.audioOutputDesc[mode.clamp(0, 2).toInt()],
              style: const TextStyle(color: Color(0xFF636366), fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }
}
