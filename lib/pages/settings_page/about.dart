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
        const SettingsInfoRow(title: 'Music Player', trailing: 'Wndavenznchole'),
        const SettingsDivider(),
        // Version — tap 3x to enable debug mode
        _VersionTile(),
        const SettingsDivider(),
      ],
    );
  }
}
