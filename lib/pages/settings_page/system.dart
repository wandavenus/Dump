part of '../settings_page.dart';

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
          builder: (_, logEnabled, __) => ValueListenableBuilder<bool>(
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

        // Verbose toggle
        ValueListenableBuilder<bool>(
          valueListenable: LogService.verboseEnabled,
          builder: (_, verbose, __) => SettingsToggleRow(
            title: 'Log Verbose & Debug',
            subtitle: 'Tampilkan level VRB dan DBG (lebih detail)',
            value: verbose,
            onChanged: LogService.setVerbose,
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
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (_) => const _LogViewerSheet(),
    );
  }
}
