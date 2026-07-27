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
          Text(context.l10n.activeEffectsStatus,
              style: TextStyle(color: c.primaryLabel, fontSize: 15)),
          const SizedBox(height: 6),
          ValueListenableBuilder<ReplayGainMode>(
            valueListenable: AudioEffectsService.replayGainMode,
             builder: (_, v, _) => _InfoLine(
                 context.l10n.statusNormalize,
                 v == ReplayGainMode.off
                     ? context.l10n.off.toUpperCase()
                     : _replayGainLabel(context, v)),
          ),
          ValueListenableBuilder<int>(
            valueListenable: AudioEffectsService.bassBoost,
             builder: (_, v, _) => _InfoLine(context.l10n.statusBassBoost, '$v / 1000'),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: AudioEffectsService.equalizerEnabled,
            builder: (_, v, _) => ValueListenableBuilder<int>(
              valueListenable: AudioEffectsService.roomPreset,
              builder: (_, r, _) => _InfoLine(
                   context.l10n.statusEqualizer,
                  v
                      ? '${AudioEffectsService.roomPresets[r]['name']} (room)'
                       : context.l10n.off.toUpperCase()),
            ),
          ),
          ValueListenableBuilder<double>(
            valueListenable: AudioEffectsService.playbackSpeed,
             builder: (_, v, _) => _InfoLine(
                 context.l10n.statusSpeed, '${v.toStringAsFixed(2)}x'),
          ),
        ],
      ),
    );
  }
}

// ─── TENTANG ─────────────────────────────────────────────────────────────────
