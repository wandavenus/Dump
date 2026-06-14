part of '../settings_page.dart';

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
          builder: (_, enabled, __) => SettingsToggleRow(
            title: 'Equalizer',
            subtitle: 'Aktifkan preset ruangan',
            value: enabled,
            onChanged: AudioEffectsService.setEqualizerEnabled,
          ),
        ),
        const SettingsDivider(),
        ValueListenableBuilder<int>(
          valueListenable: AudioEffectsService.roomPreset,
          builder: (_, idx, __) => SettingsActionRow(
            title: 'Preset Ruangan',
            trailing: AudioEffectsService.roomPresets[idx]['name'] as String,
            onTap: () => Navigator.of(context).push(
              CupertinoPageRoute<void>(
                builder: (_) => const EqualizerPage(),
              ),
            ),
          ),
        ),
        const SettingsDivider(),
      ],
    );
  }
}

// ─── SLEEP TIMER ─────────────────────────────────────────────────────────────
