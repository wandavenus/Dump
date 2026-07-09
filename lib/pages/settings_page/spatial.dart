part of '../settings_page.dart';

class _SpatialSection extends StatelessWidget {
  const _SpatialSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader('SPATIAL AUDIO'),
        const SizedBox(height: 6),

        // Accordion — slider muncul saat diketuk; fitur aktif saat slider digeser
        ValueListenableBuilder<bool>(
          valueListenable: AudioEffectsService.spatialAudio,
          builder: (_, enabled, _) => ValueListenableBuilder<int>(
            valueListenable: AudioEffectsService.spatialStrength,
            builder: (_, strength, _) => SettingsSliderRow(
              title: 'Spatial Audio',
              subtitle: enabled
                  ? '${(strength / 10).round()}%'
                  : 'Nonaktif',
              // Slider dimulai dari 0 saat fitur off
              value: enabled ? strength.toDouble() : 0.0,
              min: 0,
              max: 1000,
              onChanged: (v) async {
                if (v > 0) {
                  await AudioEffectsService.setSpatial(true);
                  await AudioEffectsService.setSpatialStrength(v.round());
                } else {
                  await AudioEffectsService.setSpatial(false);
                }
              },
              divisions: 20,
              showReset: enabled,
              onReset: () async {
                await AudioEffectsService.setSpatial(false);
              },
              expandable: true,
            ),
          ),
        ),
        const SettingsDivider(),

        // Info
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            'Spatial Audio menggunakan Android Virtualizer. '
            'Efek tergantung hardware — MIUI 12 mungkin membatasi akses AudioEffect.',
            style: TextStyle(color: Color(0xFF636366), fontSize: 12),
          ),
        ),
      ],
    );
  }
}

// ─── EQUALIZER ────────────────────────────────────────────────────────────────
