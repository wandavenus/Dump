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
              onTap: () => _pickFontSize(context, fs),
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
              onTap: () => _pickAlign(context, align),
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
              onTap: () => _pickColor(context, c),
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

  void _pickFontSize(BuildContext ctx, double cur) {
    showCupertinoModalPopup<void>(
      context: ctx,
      builder: (_) => CupertinoActionSheet(
        title: const Text('Ukuran Teks Lirik'),
        actions: [
          for (final s in [
  (label: 'Kecil (S)', value: 14.0),
  (label: 'Sedang (M)', value: 18.0),
  (label: 'Besar (L)', value: 22.0),
  (label: 'Sangat Besar (XL)', value: 26.0),
  (label: 'Kustom...', value: -1.0),
])
            CupertinoActionSheetAction(
              isDefaultAction: cur == s.value,
              onPressed: () {
  if (s.value == -1.0) {
    Navigator.pop(ctx);
    _showCustomFontSize(ctx);
    return;
  }

  LyricsSettings.setFontSize(s.value);
  Navigator.pop(ctx);
},
              child: Text(s.label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Batal'),
        ),
      ),
    );
  }

void _showCustomFontSize(BuildContext context) {
  double temp = LyricsSettings.fontSize.value;

  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Ukuran Kustom'),
      content: StatefulBuilder(
        builder: (context, setState) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${temp.round()} px'),
            Slider(
              value: temp,
              min: 12,
              max: 60,
              divisions: 28,
              onChanged: (v) {
                setState(() => temp = v);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        TextButton(
          onPressed: () {
            LyricsSettings.setFontSize(temp);
            Navigator.pop(context);
          },
          child: const Text('Simpan'),
        ),
      ],
    ),
  );
}
  
  void _pickAlign(BuildContext ctx, String cur) {
    showCupertinoModalPopup<void>(
      context: ctx,
      builder: (_) => CupertinoActionSheet(
        title: const Text('Rata Teks Lirik'),
        actions: [
          for (final o in [
            (label: 'Kiri', value: 'left'),
            (label: 'Tengah', value: 'center'),
            (label: 'Kanan', value: 'right'),
          ])
            CupertinoActionSheetAction(
              isDefaultAction: cur == o.value,
              onPressed: () { LyricsSettings.setTextAlign(o.value); Navigator.pop(ctx); },
              child: Text(o.label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Batal'),
        ),
      ),
    );
  }

  void _pickColor(BuildContext ctx, String cur) {
    showCupertinoModalPopup<void>(
      context: ctx,
      builder: (_) => CupertinoActionSheet(
        title: const Text('Warna Teks Aktif'),
        actions: [
          for (final o in [
            (label: 'Putih', value: 'white'),
            (label: 'Merah', value: 'accent'),
            (label: 'Kuning', value: 'yellow'),
          ])
            CupertinoActionSheetAction(
              isDefaultAction: cur == o.value,
              onPressed: () { LyricsSettings.setActiveColor(o.value); Navigator.pop(ctx); },
              child: Text(o.label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Batal'),
        ),
      ),
    );
  }
}

// ─── AUDIO OUTPUT ─────────────────────────────────────────────────────────────
