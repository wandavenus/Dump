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
          
          onTap: () => Navigator.of(context).push(
            ZoomFadeRoute<void>(page: const BugReportPage()),
          ),
        ),
        
        SettingsActionRow(
          title: 'Dukungan',
          
          onTap: () => Navigator.of(context).push(
            ZoomFadeRoute<void>(page: const SupportPage()),
          ),
        ),
        
        SettingsActionRow(
          title: 'Tentang App',
        
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

  // Year is stable for the app lifetime — static so it's computed once,
  // never inside build().
  static final int _currentYear = DateTime.now().year;

  @override
  Widget build(BuildContext context) {
    final year = _currentYear;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Made by Wndavenznchole',
              textAlign: TextAlign.left,
              style: TextStyle(
                color: AppColors.of(context).secondaryLabel,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '© $year Flutter Music App with Media3 Exoplayer',
              textAlign: TextAlign.left,
              style: TextStyle(
                color: AppColors.of(context).secondaryLabel,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
