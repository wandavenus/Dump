part of '../settings_page.dart';

class _EffectStatusRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Status Efek Aktif',
              style: TextStyle(color: c.primaryLabel, fontSize: 15)),
          const SizedBox(height: 6),
          ValueListenableBuilder<ReplayGainMode>(
            valueListenable: AudioEffectsService.replayGainMode,
            builder: (_, v, _) => _InfoLine('Normalize', v == ReplayGainMode.off ? 'OFF' : v.label),
          ),
          ValueListenableBuilder<int>(
            valueListenable: AudioEffectsService.bassBoost,
            builder: (_, v, _) => _InfoLine('BassBoost', '$v / 1000'),
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
