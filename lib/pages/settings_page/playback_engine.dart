part of '../settings_page.dart';

// ─── Playback Engine Section ───────────────────────────────────────────────────
//
// Engine tunneling settings — Native Media3 / ExoPlayer.

class _PlaybackEngineSection extends StatelessWidget {
  const _PlaybackEngineSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader('Engine Tunneling'),
        const SizedBox(height: 6),

        // ── Skip Silence ───────────────────────────────────────────────────
        ValueListenableBuilder<bool>(
          valueListenable: MediaCapabilitiesService.skipSilenceEnabled,
          builder: (_, v, _) => SettingsToggleRow(
            title: 'Lewati Keheningan',
            subtitle: 'Potong bagian senyap di dalam lagu (intro/outro)',
            value: v,
            onChanged: MediaCapabilitiesService.setSkipSilence,
          ),
        ),
        const SettingsDivider(),

        // ── Stereo Widening ────────────────────────────────────────────────
        ValueListenableBuilder<bool>(
          valueListenable: MediaCapabilitiesService.stereoWideningEnabled,
          builder: (_, enabled, _) => ValueListenableBuilder<double>(
            valueListenable: MediaCapabilitiesService.stereoWideningStrength,
            builder: (_, v, _) {
              final pct = (v * 100).round();
              return SettingsSliderRow(
                title: 'Pelebaran Stereo',
                subtitle: enabled ? '$pct%' : 'Nonaktif',
                value: enabled ? v : 0.0,
                min: 0.0,
                max: 1.0,
                divisions: 20,
                onChanged: (val) async {
                  if (val > 0) {
                    await MediaCapabilitiesService.setStereoWidening(true);
                    await MediaCapabilitiesService
                        .setStereoWideningStrength(val);
                  } else {
                    await MediaCapabilitiesService.setStereoWidening(false);
                  }
                },
                showReset: enabled,
                onReset: () async {
                  await MediaCapabilitiesService.setStereoWidening(false);
                },
                expandable: true,
              );
            },
          ),
        ),
        const SettingsDivider(),
      ],
    );
  }
}

// ─── Playback Stats utility ────────────────────────────────────────────────────

void _showStatsSheet(BuildContext context) {
  MediaCapabilitiesService.getPlaybackStats().then((stats) {
    if (!context.mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _PlaybackStatsSheet(stats: stats),
    );
  });
}

// ─── Playback Stats Bottom Sheet ──────────────────────────────────────────────

class _PlaybackStatsSheet extends StatelessWidget {
  const _PlaybackStatsSheet({required this.stats});
  final Map<String, dynamic>? stats;

  @override
  Widget build(BuildContext context) {
    return SwipeToDismissSheet(
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Statistik Sesi Pemutaran',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Engine: Native Media3',
                  style: TextStyle(color: Color(0xFF8E8E93), fontSize: 12),
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (stats == null)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  'Data tidak tersedia — mulai pemutaran terlebih dahulu.',
                  style: TextStyle(color: Colors.white54, fontSize: 14),
                ),
              )
            else ...[
              _StatRow(
                label: 'Waktu Putar',
                value: _fmtMs(
                    (stats!['totalPlayTimeMs'] as num?)?.toInt() ?? 0),
                icon: Icons.play_circle_outline_rounded,
              ),
              _StatRow(
                label: 'Waktu Buffering',
                value: _fmtMs(
                    (stats!['totalBufferingTimeMs'] as num?)?.toInt() ?? 0),
                icon: Icons.hourglass_bottom_rounded,
              ),
              _StatRow(
                label: 'Rebuffer',
                value:
                    '${(stats!['totalRebufferCount'] as num?)?.toInt() ?? 0} kali',
                icon: Icons.cached_rounded,
              ),
              _StatRow(
                label: 'Error',
                value:
                    '${(stats!['totalErrorCount'] as num?)?.toInt() ?? 0} kali',
                icon: Icons.error_outline_rounded,
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  static String _fmtMs(int ms) {
    if (ms <= 0) return '0 dtk';
    final total = Duration(milliseconds: ms);
    final h = total.inHours;
    final m = total.inMinutes.remainder(60);
    final s = total.inSeconds.remainder(60);
    if (h > 0) return '${h}j ${m}m ${s}d';
    if (m > 0) return '${m}m ${s}d';
    return '${s}d';
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF8E8E93)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
