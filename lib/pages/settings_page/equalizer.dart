part of '../settings_page.dart';

// ── Equalizer Section ──────────────────────────────────────────────────────────
//
// Section ini sekarang hanya menampilkan satu baris navigasi yang membuka
// EqualizerPage — halaman penuh yang berisi:
//   • Vertical band EQ sliders (jumlah band dinamis dari engine native)
//   • Preset chips (ruangan: Flat, Studio, Live Stage, dll.)
//   • Reverb presets (native Android PresetReverb, device-dependent)

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
          builder: (_, enabled, _) => ValueListenableBuilder<int>(
            valueListenable: AudioEffectsService.roomPreset,
            builder: (_, preset, _) => SettingsActionRow(
              title: 'Equalizer',
              trailing: enabled
                  ? AudioEffectsService.roomPresets[preset]['name'] as String
                  : 'Nonaktif',
              onTap: () => Navigator.of(context).push(
                CupertinoPageRoute<void>(
                  builder: (_) => const EqualizerPage(),
                ),
              ),
            ),
          ),
        ),
        const SettingsDivider(),
      ],
    );
  }
}
