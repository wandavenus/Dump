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

        // AAudio exclusive/MMAP probe
        _AAudioProbeRow(),
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

// ─── AAudio exclusive/MMAP probe row ───────────────────────────────────────────
//
// Answers a question static device info can't: when this app asks AAudio
// for SHARING_MODE_EXCLUSIVE + PERFORMANCE_MODE_LOW_LATENCY, what does the
// OS/HAL actually grant on this specific device? Opens a real, short-lived
// stream via NativeAAudioProbe, reads back the actual sharing/performance
// mode, then closes it immediately — no effect on playback.

class _AAudioProbeRow extends StatefulWidget {
  @override
  State<_AAudioProbeRow> createState() => _AAudioProbeRowState();
}

class _AAudioProbeRowState extends State<_AAudioProbeRow> {
  bool _checking = false;
  AAudioProbeReport? _report;

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cek AAudio Exclusive/MMAP',
                  style: TextStyle(color: Colors.white, fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  report == null
                      ? 'Belum diuji — buka stream nyata untuk melihat mode yang benar-benar diberikan OS'
                      : _describe(report),
                  style: TextStyle(
                    color: report == null
                        ? const Color(0xFF636366)
                        : report.isExclusiveLowLatency
                            ? const Color(0xFF30D158)
                            : const Color(0xFFFF9F0A),
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
                  onPressed: _doProbe,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF0A84FF),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Uji Sekarang', style: TextStyle(fontSize: 13)),
                ),
        ],
      ),
    );
  }

  String _describe(AAudioProbeReport report) {
    if (report.result != AAudioProbeResult.ok) {
      switch (report.result) {
        case AAudioProbeResult.unsupportedPlatform:
          return 'Tidak tersedia di platform ini';
        case AAudioProbeResult.libraryNotFound:
          return 'AAudio tidak tersedia (Android < 8.1)';
        case AAudioProbeResult.symbolMissing:
        case AAudioProbeResult.builderFailed:
        case AAudioProbeResult.openFailed:
        case AAudioProbeResult.ok:
          return report.detail.isNotEmpty
              ? report.detail
              : 'Gagal menguji AAudio';
      }
    }
    final sharing = switch (report.sharingMode) {
      AAudioSharingMode.exclusive => 'Exclusive',
      AAudioSharingMode.shared => 'Shared',
      AAudioSharingMode.unknown => 'Tidak diketahui',
    };
    final perf = switch (report.performanceMode) {
      AAudioPerformanceMode.lowLatency => 'Low Latency (MMAP)',
      AAudioPerformanceMode.powerSaving => 'Power Saving',
      AAudioPerformanceMode.none => 'None',
      AAudioPerformanceMode.unknown => 'Tidak diketahui',
    };
    if (report.isExclusiveLowLatency) {
      return 'Diberikan: $sharing · $perf — jalur cepat AAudio aktif';
    }
    return 'Diberikan: $sharing · $perf — diturunkan dari permintaan exclusive/low-latency';
  }

  Future<void> _doProbe() async {
    setState(() => _checking = true);
    final report = NativeAAudioProbe.instance.run();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _report = report;
    });
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

