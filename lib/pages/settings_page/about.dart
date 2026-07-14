part of '../settings_page.dart';

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader('TENTANG'),
        const SizedBox(height: 6),
        SettingsActionRow(
          title: 'Changelog',
          trailing: '',
          onTap: () => Navigator.of(context).push(
            ZoomFadeRoute<void>(page: const ChangelogPage()),
          ),
        ),
        const SettingsDivider(),
        SettingsActionRow(
          title: 'Laporkan Bug',
          trailing: '',
          onTap: () => Navigator.of(context).push(
            ZoomFadeRoute<void>(page: const BugReportPage()),
          ),
        ),
        const SettingsDivider(),
        SettingsActionRow(
          title: 'Dukungan',
          trailing: '',
          onTap: () => Navigator.of(context).push(
            ZoomFadeRoute<void>(page: const SupportPage()),
          ),
        ),
        const SettingsDivider(),
        SettingsActionRow(
          title: 'Tentang App',
          trailing: '',
          onTap: () => Navigator.of(context).push(
            ZoomFadeRoute<void>(page: const AboutAppPage()),
          ),
        ),
        const SettingsDivider(),
      ],
    );
  }
}
