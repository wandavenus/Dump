part of '../settings_page.dart';

// ─── Playback Stats utility ────────────────────────────────────────────────────

void _showStatsSheet(BuildContext context) {
  unawaited(
    MediaCapabilitiesService.getPlaybackStats().then((stats) {
      if (!context.mounted) return;
      unawaited(
        showModalBottomSheet<void>(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (_) => _PlaybackStatsSheet(stats: stats),
        ),
      );
    }),
  );
}

// ─── Playback Stats Bottom Sheet ──────────────────────────────────────────────

class _PlaybackStatsSheet extends StatelessWidget {
  const _PlaybackStatsSheet({required this.stats});
  final Map<String, dynamic>? stats;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final l = context.l10n;
    return SwipeToDismissSheet(
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.surface,
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
                color: c.dragHandle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l.playbackStatsTitle,
                  style: TextStyle(
                    color: c.primaryLabel,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l.playbackStatsEngine,
                  style: TextStyle(color: c.secondaryLabel, fontSize: 12),
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (stats case final s?) ...[
              _StatRow(
                label: l.playTimeLabel,
                value: _fmtMs(
                  context,
                  (s['totalPlayTimeMs'] as num?)?.toInt() ?? 0,
                ),
                icon: Icons.play_circle_outline_rounded,
              ),
              _StatRow(
                label: l.bufferingTimeLabel,
                value: _fmtMs(
                  context,
                  (s['totalBufferingTimeMs'] as num?)?.toInt() ?? 0,
                ),
                icon: Icons.hourglass_bottom_rounded,
              ),
              _StatRow(
                label: l.rebufferLabel,
                value:
                    '${(s['totalRebufferCount'] as num?)?.toInt() ?? 0} ${l.timesUnit}',
                icon: Icons.cached_rounded,
              ),
              _StatRow(
                label: l.errorLabel,
                value:
                    '${(s['totalErrorCount'] as num?)?.toInt() ?? 0} ${l.timesUnit}',
                icon: Icons.error_outline_rounded,
              ),
            ] else
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Text(
                  l.statsNotAvailable,
                  style: TextStyle(
                    color: c.primaryLabel.withValues(alpha: 0.54),
                    fontSize: 14,
                  ),
                ),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  static String _fmtMs(BuildContext context, int ms) {
    final l = context.l10n;
    if (ms <= 0) return l.durationSeconds(0);
    final total = Duration(milliseconds: ms);
    final h = total.inHours;
    final m = total.inMinutes.remainder(60);
    final s = total.inSeconds.remainder(60);
    if (h > 0) return l.durationHoursMinutesSeconds(h, m, s);
    if (m > 0) return l.durationMinutesSeconds(m, s);
    return l.durationSeconds(s);
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
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: c.secondaryLabel),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: c.primaryLabel.withValues(alpha: 0.70),
                fontSize: 14,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: c.primaryLabel,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
