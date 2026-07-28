part of '../settings_page.dart';

class _SystemSection extends StatelessWidget {
  const _SystemSection();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionHeader(l.sectionSystem),
        const SizedBox(height: 6),
        ValueListenableBuilder<int>(
          valueListenable: LogService.logCount,
          builder: (_, count, _) => SettingsActionRow(
            title: l.activityLog,
            subtitle: l.logEntryCount(count),
            onTap: () => _showLogs(context),
          ),
        ),
        const SettingsDivider(),
      ],
    );
  }

  void _showLogs(BuildContext context) {
    unawaited(
      Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => const LogPage()),
      ),
    );
  }
}
