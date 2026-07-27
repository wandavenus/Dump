part of '../log_page.dart';

/// AppBar action button showing the active logging level.
///
/// Tapping opens a bottom sheet picker. Fully self-contained — reads
/// [LogService] statics directly; no parent state is needed.
class _LogLevelSelector extends StatelessWidget {
  const _LogLevelSelector();

  // ── Visual helpers ─────────────────────────────────────────────────────────

  static ({String label, Color color, IconData icon}) _visual(
      AppLocalizations l) {
    if (!LogService.loggingEnabled.value) {
      return (
        label: l.logBadgeOff,
        color: const Color(0xFF48484A),
        icon:  Icons.tune_rounded,
      );
    }
    if (LogService.errorsOnly.value) {
      return (
        label: l.logBadgeError,
        color: const Color(0xFFFF9F0A),
        icon:  Icons.tune_rounded,
      );
    }
    if (LogService.verboseEnabled.value) {
      return (
        label: l.logBadgeVerbose,
        color: const Color(0xFF0A84FF),
        icon:  Icons.tune_rounded,
      );
    }
    return (
      label: l.logBadgeNormal,
      color: const Color(0xFF30D158),
      icon:  Icons.tune_rounded,
    );
  }

  // ── Bottom sheet ───────────────────────────────────────────────────────────

  void _showSheet(BuildContext context) {
    final c = AppColors.of(context);
    final l = context.l10n;
    unawaited(showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (_) => SafeArea(
        top: false,
        child: AnimatedBuilder(
          animation: Listenable.merge([
            LogService.loggingEnabled,
            LogService.errorsOnly,
            LogService.verboseEnabled,
          ]),
          builder: (_, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Text(
                  l.logLevelTitle,
                  style: TextStyle(
                      color: c.primaryLabel,
                      fontSize: 15,
                      fontWeight: FontWeight.w600),
                ),
              ),
              _option(
                title:    l.logLevelOff,
                subtitle: l.logLevelOffDesc,
                selected: !LogService.loggingEnabled.value,
                onTap:    () => LogService.setLoggingEnabled(false),
                primaryLabel:   c.primaryLabel,
                secondaryLabel: c.secondaryLabel,
                tertiaryLabel:  c.tertiaryLabel,
              ),
              _option(
                title:    l.logLevelErrorsOnly,
                subtitle: l.logLevelErrorsOnlyDesc,
                selected: LogService.loggingEnabled.value &&
                    LogService.errorsOnly.value,
                onTap: () async {
                  await LogService.setLoggingEnabled(true);
                  await LogService.setErrorsOnly(true);
                },
                primaryLabel:   c.primaryLabel,
                secondaryLabel: c.secondaryLabel,
                tertiaryLabel:  c.tertiaryLabel,
              ),
              _option(
                title:    l.logLevelNormal,
                subtitle: l.logLevelNormalDesc,
                selected: LogService.loggingEnabled.value &&
                    !LogService.errorsOnly.value &&
                    !LogService.verboseEnabled.value,
                onTap: () async {
                  await LogService.setLoggingEnabled(true);
                  await LogService.setErrorsOnly(false);
                  await LogService.setVerboseEnabled(false);
                },
                primaryLabel:   c.primaryLabel,
                secondaryLabel: c.secondaryLabel,
                tertiaryLabel:  c.tertiaryLabel,
              ),
              _option(
                title:    l.logLevelVerbose,
                subtitle: l.logLevelVerboseDesc,
                selected: LogService.loggingEnabled.value &&
                    !LogService.errorsOnly.value &&
                    LogService.verboseEnabled.value,
                onTap: () async {
                  await LogService.setLoggingEnabled(true);
                  await LogService.setErrorsOnly(false);
                  await LogService.setVerboseEnabled(true);
                },
                primaryLabel:   c.primaryLabel,
                secondaryLabel: c.secondaryLabel,
                tertiaryLabel:  c.tertiaryLabel,
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _option({
    required String       title,
    required String       subtitle,
    required bool         selected,
    required VoidCallback onTap,
    required Color        primaryLabel,
    required Color        secondaryLabel,
    required Color        tertiaryLabel,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color:      selected ? primaryLabel : secondaryLabel,
                      fontSize:   14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          color: tertiaryLabel, fontSize: 12)),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_rounded,
                  color: Color(0xFF30D158), size: 20),
          ],
        ),
      ),
    );
  }

  // ── Widget ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        LogService.loggingEnabled,
        LogService.errorsOnly,
        LogService.verboseEnabled,
      ]),
      builder: (_, _) {
        final v = _visual(context.l10n);
        return GestureDetector(
          onTap: () => _showSheet(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color:        v.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(v.icon, size: 11, color: v.color),
                  const SizedBox(width: 4),
                  Text(
                    v.label,
                    style: TextStyle(
                      color:      v.color,
                      fontSize:   10,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
