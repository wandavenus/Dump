part of '../settings_page.dart';

// ─── AUDIO ────────────────────────────────────────────────────────────────────

class _AudioSection extends StatelessWidget {
  const _AudioSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader('AUDIO'),
        const SizedBox(height: 6),

        // Gapless
        ValueListenableBuilder<bool>(
          valueListenable: AudioEffectsService.gaplessPlayback,
          builder: (_, v, __) => SettingsToggleRow(
            title: 'Gapless Playback',
            subtitle: 'Putar tanpa jeda antar lagu',
            value: v,
            onChanged: AudioEffectsService.setGapless,
          ),
        ),
        const SettingsDivider(),

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

        // Playback Speed
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

        // Pitch Shift
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

        // Bass Boost
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

        // Reverb
        ValueListenableBuilder<int>(
          valueListenable: AudioEffectsService.reverbPreset,
          builder: (_, v, __) => _ReverbRow(preset: v),
        ),
        const SettingsDivider(),
      ],
    );
  }
}

class _ReverbRow extends StatelessWidget {
  final int preset;
  const _ReverbRow({required this.preset});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _showReverbPicker(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Reverb',
                      style: TextStyle(color: Colors.white, fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(
                    AudioEngine.reverbSupported
                        ? AudioEffectsService.reverbPresetNames[preset]
                        : 'Tidak didukung perangkat ini',
                    style: const TextStyle(
                        color: Color(0xFF8E8E93), fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: Color(0xFF48484A), size: 20),
          ],
        ),
      ),
    );
  }

  void _showReverbPicker(BuildContext context) {
    if (!AudioEngine.reverbSupported) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Reverb tidak didukung di perangkat ini'),
        backgroundColor: Color(0xFF1C1C1E),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('Reverb'),
        actions: List.generate(
          AudioEffectsService.reverbPresetNames.length,
          (i) => CupertinoActionSheetAction(
            isDefaultAction: i == preset,
            onPressed: () {
              AudioEffectsService.setReverb(i);
              Navigator.of(context).pop();
            },
            child: Text(AudioEffectsService.reverbPresetNames[i]),
          ),
        ),
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
      ),
    );
  }
}
