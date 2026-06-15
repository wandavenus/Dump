part of '../settings_page.dart';

class _EffectStatusRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Status Efek Aktif',
              style: TextStyle(color: Colors.white, fontSize: 15)),
          const SizedBox(height: 6),
          ValueListenableBuilder<bool>(
            valueListenable: AudioEffectsService.spatialAudio,
            builder: (_, v, _) =>
                _InfoLine('Spatial', v ? 'ON (${AudioEffectsService.spatialStrength.value})' : 'OFF'),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: AudioEffectsService.audioNormalize,
            builder: (_, v, _) => _InfoLine('Normalize', v ? 'ON' : 'OFF'),
          ),
          ValueListenableBuilder<int>(
            valueListenable: AudioEffectsService.bassBoost,
            builder: (_, v, _) => _InfoLine('BassBoost', '$v / 1000'),
          ),
          ValueListenableBuilder<int>(
            valueListenable: AudioEffectsService.reverbPreset,
            builder: (_, v, _) => _InfoLine(
                'Reverb', AudioEffectsService.reverbPresetNames[v]),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: AudioEffectsService.equalizerEnabled,
            builder: (_, v, _) => ValueListenableBuilder<int>(
              valueListenable: AudioEffectsService.roomPreset,
              builder: (_, r, _) => _InfoLine(
                  'EQ',
                  v
                      ? '${AudioEffectsService.roomPresets[r]['name']} (room)'
                      : 'OFF'),
            ),
          ),
          ValueListenableBuilder<double>(
            valueListenable: AudioEffectsService.playbackSpeed,
            builder: (_, v, _) => _InfoLine('Speed', '${v.toStringAsFixed(2)}x'),
          ),
        ],
      ),
    );
  }
}

// ─── TENTANG ─────────────────────────────────────────────────────────────────
