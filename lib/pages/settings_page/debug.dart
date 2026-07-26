part of '../settings_page.dart';

class _DebugSection extends StatelessWidget {
  const _DebugSection();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
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
              child: Text(l.debugSection,
                  style: const TextStyle(
                      color: Color(0xFFF92D48),
                      fontSize: 9,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 6),

        _AudioSessionInfo(),
        const SettingsDivider(),

        _EffectStatusRow(),
        const SettingsDivider(),

        const _AAudioProbeRow(),
        const SettingsDivider(),

        SettingsActionRow(
          title: l.sessionStats,
          subtitle: l.view,
          onTap: () => _showStatsSheet(context),
        ),
        const SettingsDivider(),

        SettingsActionRow(
          title: l.exitDebugMode,
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

class _AAudioProbeRow extends StatefulWidget {
  const _AAudioProbeRow();

  @override
  State<_AAudioProbeRow> createState() => _AAudioProbeRowState();
}

class _AAudioProbeRowState extends State<_AAudioProbeRow> {
  bool _checking = false;
  AAudioProbeReport? _report;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = AppColors.of(context);
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
                Text(
                  l.checkAAudio,
                  style: TextStyle(color: c.primaryLabel, fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  report == null ? l.aaudioNotTested : _describe(context, report),
                  style: TextStyle(
                    color: report == null
                        ? c.tertiaryLabel
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
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(l.testNow, style: const TextStyle(fontSize: 13)),
                ),
        ],
      ),
    );
  }

  String _describe(BuildContext context, AAudioProbeReport report) {
    final l = context.l10n;
    if (report.result != AAudioProbeResult.ok) {
      switch (report.result) {
        case AAudioProbeResult.unsupportedPlatform:
          return l.aaudioNotAvailablePlatform;
        case AAudioProbeResult.libraryNotFound:
          return l.aaudioNotAvailableAndroid;
        case AAudioProbeResult.symbolMissing:
        case AAudioProbeResult.builderFailed:
        case AAudioProbeResult.openFailed:
        case AAudioProbeResult.ok:
          return report.detail.isNotEmpty ? report.detail : l.aaudioTestFailed;
      }
    }
    final sharing = switch (report.sharingMode) {
      AAudioSharingMode.exclusive => 'Exclusive',
      AAudioSharingMode.shared => 'Shared',
      AAudioSharingMode.unknown => 'Unknown',
    };
    final perf = switch (report.performanceMode) {
      AAudioPerformanceMode.lowLatency => 'Low Latency (MMAP)',
      AAudioPerformanceMode.powerSaving => 'Power Saving',
      AAudioPerformanceMode.none => 'None',
      AAudioPerformanceMode.unknown => 'Unknown',
    };
    if (report.isExclusiveLowLatency) {
      return 'Granted: $sharing · $perf — AAudio fast path active';
    }
    return 'Granted: $sharing · $perf — downgraded from exclusive/low-latency';
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
