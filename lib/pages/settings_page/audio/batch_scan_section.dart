part of '../../settings_page.dart';

class _BatchScanSection extends StatefulWidget {
  const _BatchScanSection();

  @override
  State<_BatchScanSection> createState() => _BatchScanSectionState();
}

class _BatchScanSectionState extends State<_BatchScanSection> {
  Future<void> _confirmAndStartScan(BuildContext context) async {
    final l = context.l10n;
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: Text(l.scanLibraryConfirmTitle),
        content: Text(l.scanLibraryConfirmBody),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.cancel),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.scanLibrary),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await _startScan(context);
    }
  }

  Future<void> _startScan(BuildContext context) async {
    final l = context.l10n;
    try {
      final songs = await MediaStoreService.getSongs();
      if (!context.mounted) return;
      if (songs.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.noSongsInLibrary)));
        return;
      }
      // Library scan is read/compute-only. Permanent tag changes must go
      // through the explicit write action so a scan cannot unexpectedly
      // rewrite user files.
      unawaited(ReplayGainService.scanLibrary(songs));
    } on Exception catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.scanLibraryLoadFailed(e.toString()))),
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
            progress: progress,
            onScanAgain: () => _confirmAndStartScan(context),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ScanIdleRow(onTap: () => _confirmAndStartScan(context)),
            const _RemoveRgRow(),
          ],
        );
      },
    );
  }
}

/// Explicit "remove ReplayGain tags from the whole library" action — the only
/// surviving tag-mutation UI, deliberately placed in Settings (Audio Normalize).
class _RemoveRgRow extends StatefulWidget {
  const _RemoveRgRow();

  @override
  State<_RemoveRgRow> createState() => _RemoveRgRowState();
}

class _RemoveRgRowState extends State<_RemoveRgRow> {
  bool _busy = false;

  Future<void> _confirmAndRemove(BuildContext context) async {
    final l = context.l10n;
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: Text(l.rgRemoveConfirmTitle),
        content: Text(l.rgRemoveConfirmBody),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.cancel),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.rgRemoveTagsAction),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await _removeAll(context);
    }
  }

  Future<void> _removeAll(BuildContext context) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    messenger.showSnackBar(
      SnackBar(
        content: Text(l.rgRemoveRunning),
        duration: const Duration(seconds: 2),
      ),
    );
    try {
      final songs = await MediaStoreService.getSongs();
      if (!context.mounted) return;
      final result = await ReplayGainService.removeReplayGainFromLibrary(songs);
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      final Text message;
      if (result.failed == 0) {
        message = Text(l.rgRemoveLibrarySuccess(result.removed));
      } else if (result.removed == 0) {
        message = Text(l.rgRemoveFailed);
      } else {
        message = Text(l.rgRemoveLibraryPartial(result.removed, result.failed));
      }
      messenger.showSnackBar(SnackBar(content: message));
    } on Exception catch (e) {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text(l.scanLibraryLoadFailed(e.toString()))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = AppColors.of(context);
    return InkWell(
      onTap: _busy ? null : () => _confirmAndRemove(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              _busy
                  ? Icons.hourglass_top_rounded
                  : Icons.delete_outline_rounded,
              color: c.primaryLabel.withValues(alpha: 0.38),
              size: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l.rgRemoveTagsAction,
                style: TextStyle(color: c.primaryLabel, fontSize: 15),
              ),
            ),
            if (_busy)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }
}

class _ScanIdleRow extends StatelessWidget {
  const _ScanIdleRow({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
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
                  Text(
                    l.scanLibrary,
                    style: TextStyle(color: c.primaryLabel, fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l.scanLibrarySubtitle,
                    style: TextStyle(color: c.secondaryLabel, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.graphic_eq_rounded,
              color: c.primaryLabel.withValues(alpha: 0.38),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanProgressRow extends StatelessWidget {
  const _ScanProgressRow({required this.progress});
  final BatchScanProgress progress;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
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
                      ? l.scanPreparing
                      : progress.currentTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.primaryLabel, fontSize: 15),
                ),
              ),
              Text(
                '${progress.done}/${progress.total}',
                style: TextStyle(color: c.secondaryLabel, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: pct,
            backgroundColor: c.primaryLabel.withValues(alpha: 0.08),
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFF92D48)),
          ),
        ],
      ),
    );
  }
}

class _ScanResultRow extends StatelessWidget {
  const _ScanResultRow({required this.progress, required this.onScanAgain});
  final BatchScanProgress progress;
  final VoidCallback onScanAgain;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = AppColors.of(context);
    final String subtitle;
    if (progress.cancelled) {
      subtitle = l.scanCancelled(progress.succeeded);
    } else if (progress.failed == 0) {
      subtitle = l.scanSuccess(progress.succeeded);
    } else {
      subtitle = l.scanPartial(progress.succeeded, progress.failed);
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
                  Text(
                    l.scanLibrary,
                    style: TextStyle(color: c.primaryLabel, fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(color: c.secondaryLabel, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.replay_rounded,
              color: c.primaryLabel.withValues(alpha: 0.38),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}
