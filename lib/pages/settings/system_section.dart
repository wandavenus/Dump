part of '../settings_page.dart';

// ─── SISTEM ───────────────────────────────────────────────────────────────────

class _SystemSection extends StatelessWidget {
  const _SystemSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader('SISTEM'),
        const SizedBox(height: 6),

        // Logging toggle
        ValueListenableBuilder<bool>(
          valueListenable: LogService.loggingEnabled,
          builder: (_, enabled, __) => SettingsToggleRow(
            title: 'Logging Aktif',
            subtitle: 'Catat aktivitas & error app',
            value: enabled,
            onChanged: LogService.setLoggingEnabled,
          ),
        ),
        const SettingsDivider(),

        // Errors only toggle
        ValueListenableBuilder<bool>(
          valueListenable: LogService.loggingEnabled,
          builder: (_, logEnabled, __) =>
              ValueListenableBuilder<bool>(
            valueListenable: LogService.errorsOnly,
            builder: (_, errOnly, __) => SettingsToggleRow(
              title: 'Error & Peringatan Saja',
              subtitle: 'Sembunyikan log informasi biasa',
              value: errOnly,
              onChanged: (v) async {
                if (logEnabled) await LogService.setErrorsOnly(v);
              },
            ),
          ),
        ),
        const SettingsDivider(),

        // Log viewer
        ValueListenableBuilder<int>(
          valueListenable: LogService.logCount,
          builder: (_, count, __) => SettingsActionRow(
            title: 'Log Aktivitas',
            trailing: '$count entri',
            onTap: () => _showLogs(context),
          ),
        ),
        const SettingsDivider(),

        // Clear logs
        SettingsActionRow(
          title: 'Bersihkan Log',
          trailing: '',
          onTap: LogService.clear,
          isDestructive: true,
        ),
        const SettingsDivider(),
      ],
    );
  }

  void _showLogs(BuildContext context) {
    final logs = LogService.getLogs();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (_, sc) => Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Log Aktivitas',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                _LogFilterChips(),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: logs.isEmpty
                  ? const Center(
                      child: Text('Belum ada log',
                          style: TextStyle(color: Color(0xFF8E8E93))))
                  : ListView.builder(
                      controller: sc,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: logs.length,
                      itemBuilder: (_, i) {
                        final log = logs[logs.length - 1 - i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                margin: const EdgeInsets.only(top: 4, right: 6),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: log.level == LogLevel.error
                                      ? const Color(0xFFF92D48)
                                      : log.level == LogLevel.warning
                                          ? Colors.orange
                                          : const Color(0xFF48484A),
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          '[${log.category}]',
                                          style: TextStyle(
                                            color: log.level == LogLevel.error
                                                ? const Color(0xFFF92D48)
                                                : log.level == LogLevel.warning
                                                    ? Colors.orange
                                                    : const Color(0xFF8E8E93),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${log.timestamp.hour.toString().padLeft(2,'0')}:'
                                          '${log.timestamp.minute.toString().padLeft(2,'0')}:'
                                          '${log.timestamp.second.toString().padLeft(2,'0')}',
                                          style: const TextStyle(
                                              color: Color(0xFF48484A),
                                              fontSize: 10),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      log.message,
                                      style: const TextStyle(
                                          color: Colors.white70, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogFilterChips extends StatefulWidget {
  @override
  State<_LogFilterChips> createState() => _LogFilterChipsState();
}

class _LogFilterChipsState extends State<_LogFilterChips> {
  int _filter = 0; // 0=all, 1=errors, 2=warnings

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Chip(label: 'Semua',    selected: _filter == 0, onTap: () => setState(() => _filter = 0)),
        const SizedBox(width: 4),
        _Chip(label: 'Error',    selected: _filter == 1, onTap: () => setState(() => _filter = 1), color: const Color(0xFFF92D48)),
        const SizedBox(width: 4),
        _Chip(label: 'Warning',  selected: _filter == 2, onTap: () => setState(() => _filter = 2), color: Colors.orange),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color = const Color(0xFF8E8E93),
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? color : const Color(0xFF48484A), width: 0.5),
        ),
        child: Text(label, style: TextStyle(color: color, fontSize: 11)),
      ),
    );
  }
}
