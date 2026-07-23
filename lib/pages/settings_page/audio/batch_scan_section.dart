part of '../../settings_page.dart';

// ─── Batch ReplayGain Scan section ────────────────────────────────────────────
//
// Sits inside the _ReplayGainSection collapsible area.
// Shows an action row (idle), progress indicator (scanning), or a brief result
// summary (finished). The actual scan runs as a background Future so the UI
// stays responsive while MediaCodec decodes each file.

class _BatchScanSection extends StatefulWidget {
  const _BatchScanSection();

  @override
  State<_BatchScanSection> createState() => _BatchScanSectionState();
}

class _BatchScanSectionState extends State<_BatchScanSection> {
  Future<void> _startScan(BuildContext context) async {
    try {
      final songs = await MediaStoreService.getSongs();
      if (!context.mounted) return;
      if (songs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Tidak ada lagu ditemukan di library.')),
        );
        return;
      }
      // Write tags automatically after scan — no manual confirmation needed.
      unawaited(ReplayGainService.scanLibrary(songs, writeTags: true));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memuat library: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BatchScanProgress>(
      valueListenable: ReplayGainService.scanProgress,
      builder: (context, progress, _) {
        if (progress.running) {
          return _ScanProgressRow(progress: progress);
        }
        if (progress.finished) {
          return _ScanResultRow(
            progress:    progress,
            onScanAgain: () => _startScan(context),
          );
        }
        return _ScanIdleRow(onTap: () => _startScan(context));
      },
    );
  }
}

// ── Idle state ────────────────────────────────────────────────────────────────

class _ScanIdleRow extends StatelessWidget {
  const _ScanIdleRow({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Scan Library',
                      style: TextStyle(color: c.primaryLabel, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(
                    'Hitung ReplayGain untuk lagu yang belum punya data',
                    style: TextStyle(color: c.secondaryLabel, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.graphic_eq_rounded,
                color: c.primaryLabel.withValues(alpha: 0.38), size: 18),
          ],
        ),
      ),
    );
  }
}

// ── Scanning in progress ──────────────────────────────────────────────────────

class _ScanProgressRow extends StatelessWidget {
  const _ScanProgressRow({required this.progress});
  final BatchScanProgress progress;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final pct = progress.total > 0
        ? (progress.done / progress.total).clamp(0.0, 1.0)
        : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  progress.currentTitle.isEmpty
                      ? 'Mempersiapkan...'
                      : progress.currentTitle,
                  style: TextStyle(color: c.primaryLabel, fontSize: 14),
                  maxLines:  1,
                  overflow:  TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${progress.done} / ${progress.total}',
                style: TextStyle(
                    color: c.secondaryLabel, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value:      pct,
              backgroundColor: c.primaryLabel.withValues(alpha: 0.12),
              valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFFF92D48)),
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: ReplayGainService.cancelScan,
            child: const Text('Batalkan',
                style: TextStyle(color: Color(0xFFF92D48), fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ── Scan finished ─────────────────────────────────────────────────────────────

class _ScanResultRow extends StatelessWidget {
  const _ScanResultRow({
    required this.progress,
    required this.onScanAgain,
  });
  final BatchScanProgress progress;
  final VoidCallback       onScanAgain;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final String subtitle;
    if (progress.cancelled) {
      subtitle = 'Dibatalkan · ${progress.succeeded} lagu berhasil';
    } else if (progress.failed == 0) {
      subtitle = '${progress.succeeded} lagu berhasil dipindai';
    } else {
      subtitle = '${progress.succeeded} berhasil, ${progress.failed} gagal';
    }

    return InkWell(
      onTap: onScanAgain,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Scan Library',
                      style: TextStyle(color: c.primaryLabel, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          color: c.secondaryLabel, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.replay_rounded,
                color: c.primaryLabel.withValues(alpha: 0.38), size: 18),
          ],
        ),
      ),
    );
  }
}
