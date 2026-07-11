part of '../settings_page.dart';

class _DebugSection extends StatelessWidget {
  const _DebugSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 16),
              child: Text(
                'DEBUG',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFFF92D48),
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFF92D48).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('MODE AKTIF',
                  style: TextStyle(
                      color: Color(0xFFF92D48),
                      fontSize: 9,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Audio session info
        _AudioSessionInfo(),
        const SettingsDivider(),

        // Effect status
        _EffectStatusRow(),
        const SettingsDivider(),

        // Leak Tracker (hanya debug build)
        if (kDebugMode) ...[
          _LeakTrackerRow(),
          const SettingsDivider(),
        ],

        // Statistik Sesi
        SettingsActionRow(
          title: 'Statistik Sesi',
          trailing: 'Lihat',
          onTap: () => _showStatsSheet(context),
        ),
        const SettingsDivider(),

        // Exit debug
        SettingsActionRow(
          title: 'Keluar Mode Debug',
          trailing: '',
          onTap: () {
            PlayerSheetController.close();
            _DebugState.enabled.value = false;
          },
          isDestructive: true,
        ),
        const SettingsDivider(),
      ],
    );
  }
}

// ─── Leak Tracker row ─────────────────────────────────────────────────────────

class _LeakTrackerRow extends StatefulWidget {
  @override
  State<_LeakTrackerRow> createState() => _LeakTrackerRowState();
}

class _LeakTrackerRowState extends State<_LeakTrackerRow> {
  bool _checking = false;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: LogService.loggingEnabled,
      builder: (_, loggingOn, _) {
        final running = loggingOn && LeakTrackerService.isRunning;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Leak Tracker',
                      style: TextStyle(color: Colors.white, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      running
                          ? 'Aktif — auto-check setiap 60 s'
                          : 'Tidak aktif (aktifkan logging dulu)',
                      style: TextStyle(
                        color: running
                            ? const Color(0xFF30D158)
                            : const Color(0xFF636366),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _checking
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF0A84FF),
                      ),
                    )
                  : TextButton(
                      onPressed: running ? _doCheck : null,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF0A84FF),
                        disabledForegroundColor:
                            const Color(0xFF636366).withValues(alpha: 0.5),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Cek Sekarang',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _doCheck() async {
    setState(() => _checking = true);
    await LeakTrackerService.checkNow();
    if (!mounted) return;
    setState(() => _checking = false);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const LogPage(initialCategory: 'LeakTracker'),
      ),
    );
  }
}

