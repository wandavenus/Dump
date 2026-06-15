part of '../settings_page.dart';

class _LyricsAppearanceRows extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ValueListenableBuilder<double>(
          valueListenable: LyricsSettings.fontSize,
          builder: (_, fs, __) {
            final label = fs <= 14 ? 'Kecil (S)' : fs <= 18 ? 'Sedang (M)' : fs <= 22 ? 'Besar (L)' : 'Sangat Besar (XL)';
            return SettingsActionRow(
              title: 'Ukuran Teks Lirik',
              trailing: label,
              onTap: () => _lyricPickFontSize(context, fs),
            );
          },
        ),
        const SettingsDivider(),
        ValueListenableBuilder<String>(
          valueListenable: LyricsSettings.textAlign,
          builder: (_, align, __) {
            final label = align == 'center' ? 'Tengah' : align == 'right' ? 'Kanan' : 'Kiri';
            return SettingsActionRow(
              title: 'Rata Teks',
              trailing: label,
              onTap: () => _lyricPickAlign(context, align),
            );
          },
        ),
        const SettingsDivider(),
        ValueListenableBuilder<String>(
          valueListenable: LyricsSettings.activeColor,
          builder: (_, c, __) {
            final label = c == 'accent' ? 'Merah' : c == 'yellow' ? 'Kuning' : 'Putih';
            return SettingsActionRow(
              title: 'Warna Teks Aktif',
              trailing: label,
              onTap: () => _lyricPickColor(context, c),
            );
          },
        ),
        const SettingsDivider(),
        ValueListenableBuilder<double>(
          valueListenable: LyricsSettings.bgDim,
          builder: (_, v, __) => SettingsSliderRow(
            title: 'Kegelapan Latar',
            subtitle: '${(v * 100).round()}%',
            value: v,
            min: 0.2,
            max: 0.95,
            divisions: 15,
            onChanged: LyricsSettings.setBgDim,
          ),
        ),
        const SettingsDivider(),
        ValueListenableBuilder<double>(
          valueListenable: LyricsSettings.blurStrength,
          builder: (_, v, __) => SettingsSliderRow(
            title: 'Blur Latar',
            subtitle: v == 0 ? 'Nonaktif' : '${v.round()}',
            value: v,
            min: 0,
            max: 50,
            divisions: 10,
            onChanged: LyricsSettings.setBlurStrength,
          ),
        ),
        const SettingsDivider(),
        ValueListenableBuilder<bool>(
          valueListenable: LyricsSettings.showSource,
          builder: (_, v, __) => SettingsToggleRow(
            title: 'Tampilkan Sumber Lirik',
            subtitle: 'Label "Dari internet / Dari file" di halaman lirik',
            value: v,
            onChanged: LyricsSettings.setShowSource,
          ),
        ),
        const SettingsDivider(),
      ],
    );
  }
}

// ─── AUDIO OUTPUT ─────────────────────────────────────────────────────────────
