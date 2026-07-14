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
        const _AboutFooter(),
      ],
    );
  }
}

class _AboutFooter extends StatelessWidget {
  const _AboutFooter();

  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Made by Wndavenznchole',
              textAlign: TextAlign.left,
              style: TextStyle(
                color: Color(0xFF8E8E93),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '© $year Flutter Music App x Apple Music',
              textAlign: TextAlign.left,
              style: const TextStyle(
                color: Color(0xFF8E8E93),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
