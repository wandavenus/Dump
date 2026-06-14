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

        // Jalur folder .lrc
        _LyricsPathRow(),
        const SettingsDivider(),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Text(
            'Sumber lirik: tag file (MP3/M4A/FLAC/OGG) → folder .lrc → internet.',
            style: TextStyle(color: Color(0xFF636366), fontSize: 12),
          ),
        ),
        const SizedBox(height: 8),

        // ── Pengaturan tampilan lirik ──────────────────────────────────────
        const SettingsSectionHeader('TAMPILAN LIRIK'),
        const SizedBox(height: 6),
        _LyricsAppearanceRows(),
      ],
    );
  }
}
