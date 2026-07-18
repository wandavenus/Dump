part of '../log_page.dart';

/// AppBar action button showing the active logging level.
///
/// Tapping opens a bottom sheet picker. Fully self-contained — reads
/// [LogService] statics directly; no parent state is needed.
class _LogLevelSelector extends StatelessWidget {
  const _LogLevelSelector();

  // ── Visual helpers ─────────────────────────────────────────────────────────

  static ({String label, Color color, IconData icon}) _visual() {
    if (!LogService.loggingEnabled.value) {
      return (
        label: 'OFF',
        color: const Color(0xFF48484A),
        icon:  Icons.tune_rounded,
      );
    }
    if (LogService.errorsOnly.value) {
      return (
        label: 'ERR',
        color: const Color(0xFFFF9F0A),
        icon:  Icons.tune_rounded,
      );
    }
    if (LogService.verboseEnabled.value) {
      return (
        label: 'VRB',
        color: const Color(0xFF0A84FF),
        icon:  Icons.tune_rounded,
      );
    }
    return (
      label: 'LOG',
      color: const Color(0xFF30D158),
      icon:  Icons.tune_rounded,
    );
  }

  // ── Bottom sheet ───────────────────────────────────────────────────────────

  void _showSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
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
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Text(
                  'Level Log',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600),
                ),
              ),
              _option(
                title:    'Nonaktif',
                subtitle: 'Logging dimatikan',
                selected: !LogService.loggingEnabled.value,
                onTap:    () => LogService.setLoggingEnabled(false),
              ),
              _option(
                title:    'Error & Peringatan Saja',
                subtitle: 'Sembunyikan log info & verbose',
                selected: LogService.loggingEnabled.value &&
                    LogService.errorsOnly.value,
                onTap: () async {
                  await LogService.setLoggingEnabled(true);
                  await LogService.setErrorsOnly(true);
                },
              ),
              _option(
                title:    'Normal',
                subtitle: 'Log info, error & peringatan',
                selected: LogService.loggingEnabled.value &&
                    !LogService.errorsOnly.value &&
                    !LogService.verboseEnabled.value,
                onTap: () async {
                  await LogService.setLoggingEnabled(true);
                  await LogService.setErrorsOnly(false);
                  await LogService.setVerboseEnabled(false);
                },
              ),
              _option(
                title:    'Log Verbose',
                subtitle: 'Tampilkan log detail',
                selected: LogService.loggingEnabled.value &&
                    !LogService.errorsOnly.value &&
                    LogService.verboseEnabled.value,
                onTap: () async {
                  await LogService.setLoggingEnabled(true);
                  await LogService.setErrorsOnly(false);
                  await LogService.setVerboseEnabled(true);
                },
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _option({
    required String      title,
    required String      subtitle,
    required bool        selected,
    required VoidCallback onTap,
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
                      color:      selected ? Colors.white : const Color(0xFFAEAEB2),
                      fontSize:   14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          color: Color(0xFF636366), fontSize: 12)),
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
        final v = _visual();
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
