part of '../settings_page.dart';

// ── Equalizer Section ──────────────────────────────────────────────────────────
//
// Entry point di Settings → membuka EqualizerPage (full-screen push navigation).
// EqualizerPage berisi:
//   • Preset chips EQ (Flat, Rock, Pop, Jazz, Classical, dll.)
//   • Vertical band sliders — jumlah band & frekuensi dari android.media.audiofx.Equalizer

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
                    ZoomFadeRoute<void>(page: const EqualizerPage()),
                  ),
                );
              },
            );
          },
        ),
        const SettingsDivider(),

        // ── Kecepatan Putar ───────────────────────────────────────────────────
        ValueListenableBuilder<double>(
          valueListenable: AudioEffectsService.playbackSpeed,
          builder: (_, v, _) => SettingsSliderRow(
            title: 'Kecepatan Putar',
            subtitle: '${v.toStringAsFixed(2)}x',
            value: v,
            min: 0.25,
            max: 3.0,
            onChanged: AudioEffectsService.setSpeed,
            divisions: 22,
            showReset: v != 1.0,
            onReset: () => AudioEffectsService.setSpeed(1.0),
            expandable: true,
          ),
        ),
        const SettingsDivider(),

        // ── Pitch Shift ───────────────────────────────────────────────────────
        ValueListenableBuilder<double>(
          valueListenable: AudioEffectsService.pitchShift,
          builder: (_, v, _) => SettingsSliderRow(
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
            expandable: true,
          ),
        ),
        const SettingsDivider(),

        // ── Bass Boost ────────────────────────────────────────────────────────
        ValueListenableBuilder<int>(
          valueListenable: AudioEffectsService.bassBoost,
          builder: (_, v, _) => SettingsSliderRow(
            title: 'Bass Boost',
            subtitle: v == 0
                ? 'Nonaktif'
                : DeviceDsp.bassBoostSupported
                    ? '${(v / 10).round()}%'
                    : 'Tidak didukung perangkat ini',
            value: v.toDouble(),
            min: 0,
            max: 1000,
            onChanged: (val) => AudioEffectsService.setBassBoost(val.round()),
            divisions: 20,
            showReset: v != 0,
            onReset: () => AudioEffectsService.setBassBoost(0),
            expandable: true,
          ),
        ),
        const SettingsDivider(),

        // ── Compressor ────────────────────────────────────────────────────────
        //
        // Ratio drives on/off directly: 1:1 = no compression (off). No
        // separate switch — moving the slider above 1:1 engages it.
        ValueListenableBuilder<double>(
          valueListenable: AudioEffectsService.compressorRatio,
          builder: (_, ratio, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SettingsSliderRow(
                title: 'Compressor',
                subtitle: ratio <= 1.0
                    ? 'Nonaktif'
                    : '${ratio.toStringAsFixed(1)}:1',
                value: ratio,
                min: 1.0,
                max: 20.0,
                onChanged: AudioEffectsService.setCompressorRatio,
                divisions: 38,
                showReset: ratio != 1.0,
                onReset: () => AudioEffectsService.setCompressorRatio(1.0),
                expandable: true,
              ),
              if (ratio > 1.0)
                ValueListenableBuilder<double>(
                  valueListenable: AudioEffectsService.compressorThreshold,
                  builder: (_, v, _) => SettingsSliderRow(
                    title: 'Compressor Threshold',
                    subtitle: '${v.toStringAsFixed(0)} dB',
                    value: v,
                    min: -60.0,
                    max: 0.0,
                    onChanged: AudioEffectsService.setCompressorThreshold,
                    divisions: 60,
                    showReset: v != -20.0,
                    onReset: () =>
                        AudioEffectsService.setCompressorThreshold(-20.0),
                  ),
                ),
            ],
          ),
        ),
        const SettingsDivider(),

        // ── Limiter ───────────────────────────────────────────────────────────
        //
        // Ceiling drives on/off directly: 0 dB (top of range) = off. No
        // separate switch — moving the slider below 0 engages it.
        ValueListenableBuilder<double>(
          valueListenable: AudioEffectsService.limiterThreshold,
          builder: (_, v, _) => SettingsSliderRow(
            title: 'Limiter',
            subtitle: v >= 0.0 ? 'Nonaktif' : '${v.toStringAsFixed(1)} dB',
            value: v,
            min: -24.0,
            max: 0.0,
            onChanged: AudioEffectsService.setLimiterThreshold,
            divisions: 48,
            showReset: v != 0.0,
            onReset: () => AudioEffectsService.setLimiterThreshold(0.0),
            expandable: true,
          ),
        ),
        const SettingsDivider(),

        // ── Soft Clipper ──────────────────────────────────────────────────────
        //
        // Threshold drives on/off directly: 0 dB (top of range) = off. No
        // separate switch — moving the slider below 0 engages it.
        ValueListenableBuilder<double>(
          valueListenable: AudioEffectsService.softClipperThreshold,
          builder: (_, v, _) => SettingsSliderRow(
            title: 'Soft Clipper',
            subtitle: v >= 0.0 ? 'Nonaktif' : '${v.toStringAsFixed(1)} dB',
            value: v,
            min: -12.0,
            max: 0.0,
            onChanged: AudioEffectsService.setSoftClipperThreshold,
            divisions: 24,
            showReset: v != 0.0,
            onReset: () => AudioEffectsService.setSoftClipperThreshold(0.0),
            expandable: true,
          ),
        ),
        const SettingsDivider(),
      ],
    );
  }
}
