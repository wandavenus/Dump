part of '../settings_page.dart';

class _LyricsSection extends StatelessWidget {
  const _LyricsSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader('LIRIK'),
        const SizedBox(height: 6),

        // ── Pengaturan tampilan lirik ──────────────────────────────────────
        const SettingsSectionHeader('TAMPILAN LIRIK'),
        const SizedBox(height: 6),
        _LyricsAppearanceRows(),
      ],
    );
  }
}
