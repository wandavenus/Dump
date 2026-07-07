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

        ValueListenableBuilder<bool>(
          valueListenable: LogService.loggingEnabled,
          builder: (_, enabled, _) => SettingsToggleRow(
            title: 'Logging Aktif',
            subtitle: 'Catat aktivitas & error app',
            value: enabled,
            onChanged: LogService.setLoggingEnabled,
          ),
        ),
        const SettingsDivider(),

        ValueListenableBuilder<bool>(
  valueListenable: LogService.loggingEnabled,
  builder: (_, logEnabled, _) => ValueListenableBuilder<bool>(
    valueListenable: LogService.errorsOnly,
    builder: (_, errOnly, _) => SettingsToggleRow(
      title: 'Error & Peringatan Saja',
      subtitle: 'Sembunyikan log info & verbose',
      value: errOnly,
      onChanged: (v) async {
  if (logEnabled) {
    await LogService.setErrorsOnly(v);
  }
},
    ),
  ),
),
        const SettingsDivider(),

        ValueListenableBuilder<bool>(
          valueListenable: LogService.loggingEnabled,
          builder: (_, logEnabled, _) => ValueListenableBuilder<bool>(
            valueListenable: LogService.errorsOnly,
            builder: (_, errOnly, _) => ValueListenableBuilder<bool>(
              valueListenable: LogService.verboseEnabled,
              builder: (_, verbose, _) => SettingsToggleRow(
                title: 'Log Verbose',
                subtitle: 'Tampilkan log detail',
                value: verbose,
                onChanged: (v) async {
                  if (logEnabled && !errOnly) {
                    await LogService.setVerboseEnabled(v);
                  }
                },
              ),
            ),
          ),
        ),
        const SettingsDivider(),

        ValueListenableBuilder<int>(
          valueListenable: LogService.logCount,
          builder: (_, count, _) => SettingsActionRow(
            title: 'Log Aktivitas',
            trailing: '$count entri',
            onTap: () => _showLogs(context),
          ),
        ),
        const SettingsDivider(),

        const SettingsActionRow(
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
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LogPage()),
    );
  }
}

// Log viewer dipindah ke lib/pages/log_page.dart
