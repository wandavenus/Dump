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

        // Toggle
        ValueListenableBuilder<bool>(
          valueListenable: AudioEffectsService.spatialAudio,
          builder: (_, v, _) => SettingsToggleRow(
            title: 'Spatial Audio',
            subtitle: AudioEngine.virtualizerSupported
                ? 'Virtualizer 3D surround (Android AudioEffect)'
                : 'Tidak didukung perangkat ini',
            value: v,
            onChanged: AudioEffectsService.setSpatial,
          ),
        ),
        const SettingsDivider(),

        // Strength slider
        ValueListenableBuilder<bool>(
          valueListenable: AudioEffectsService.spatialAudio,
          builder: (_, enabled, _) =>
              ValueListenableBuilder<int>(
            valueListenable: AudioEffectsService.spatialStrength,
            builder: (_, strength, _) => SettingsSliderRow(
              title: 'Kekuatan Spatial',
              subtitle: enabled
                  ? '${(strength / 10).round()}%'
                  : 'Aktifkan Spatial Audio terlebih dahulu',
              value: strength.toDouble(),
              min: 0,
              max: 1000,
              onChanged: enabled
                  ? (v) => AudioEffectsService.setSpatialStrength(v.round())
                  : (_) async {},
              divisions: 20,
              showReset: enabled && strength != 1000,
              onReset: () => AudioEffectsService.setSpatialStrength(1000),
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
