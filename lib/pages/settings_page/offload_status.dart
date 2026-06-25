part of '../settings_page.dart';

class _OffloadStatusInfo extends StatelessWidget {
  const _OffloadStatusInfo();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Status Audio Offload',
            style: TextStyle(color: Colors.white, fontSize: 15),
          ),
          const SizedBox(height: 6),

          // ── Scheduling note (Media3 1.10.1) ─────────────────────────────
          // experimentalSetOffloadSchedulingEnabled was removed in Media3 1.10.1.
          // Scheduling is now managed internally by Media3; this row shows the
          // stored preference only — it has no effect on native behaviour.
          ValueListenableBuilder<bool>(
            valueListenable: AudioEffectsService.offloadSchedulingEnabled,
            builder: (_, enabled, _) => _InfoLine(
              'Scheduling (pref)',
              enabled
                  ? 'ON (disimpan) — Media3 1.10.1 kelola internal; tidak berpengaruh'
                  : 'OFF (disimpan) — Media3 1.10.1 kelola internal; tidak berpengaruh',
            ),
          ),

          // ── OS grant status (real-time from native AudioOffloadListener) ─
          ValueListenableBuilder<bool>(
            valueListenable: AudioEffectsService.offloadOsGranted,
            builder: (_, granted, _) => _OffloadGrantedLine(granted: granted),
          ),

          // ── Incompatibility hints ────────────────────────────────────────
          ValueListenableBuilder<double>(
            valueListenable: AudioEffectsService.crossfadeDuration,
            builder: (_, dur, _) => _InfoLine(
              'Crossfade',
              dur > 0
                  ? '${dur.toStringAsFixed(0)}s — offload blocked (dual-player)'
                  : 'Off — no block',
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: AudioEffectsService.equalizerEnabled,
            builder: (_, eq, _) => ValueListenableBuilder<bool>(
              valueListenable: AudioEffectsService.spatialAudio,
              builder: (_, spatial, _) => ValueListenableBuilder<bool>(
                valueListenable: AudioEffectsService.audioNormalize,
                builder: (_, norm, _) {
                  final effects = <String>[];
                  if (eq) effects.add('EQ');
                  if (spatial) effects.add('Spatial');
                  if (norm) effects.add('Normalize');
                  return _InfoLine(
                    'SW Effects',
                    effects.isEmpty
                        ? 'None — offload eligible'
                        : '${effects.join(', ')} — offload blocked',
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OffloadGrantedLine extends StatelessWidget {
  final bool granted;
  const _OffloadGrantedLine({required this.granted});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const Text(
            'OS Granted: ',
            style: TextStyle(color: Color(0xFF8E8E93), fontSize: 12),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: granted
                  ? const Color(0xFF30D158).withValues(alpha: 0.2)
                  : const Color(0xFF636366).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              granted ? 'YES — DSP aktif' : 'NO — CPU rendering',
              style: TextStyle(
                color: granted
                    ? const Color(0xFF30D158)
                    : const Color(0xFF8E8E93),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
