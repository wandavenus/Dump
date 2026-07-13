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
