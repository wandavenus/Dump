part of '../settings_page.dart';

// ─── LIRIK ────────────────────────────────────────────────────────────────────

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

class _LyricsPathRow extends StatefulWidget {
  @override
  State<_LyricsPathRow> createState() => _LyricsPathRowState();
}

class _LyricsPathRowState extends State<_LyricsPathRow> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AudioEffectsService.lyricsPath,
      builder: (_, path, __) => InkWell(
        onTap: () => _showPathDialog(context, path),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              const Icon(Icons.lyrics, color: Color(0xFF8E8E93), size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Jalur Lirik',
                        style: TextStyle(color: Colors.white, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(
                      path.isEmpty ? 'Belum ditentukan' : path,
                      style: const TextStyle(
                          color: Color(0xFF8E8E93), fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (path.isNotEmpty)
                GestureDetector(
                  onTap: () => AudioEffectsService.setLyricsPath(''),
                  child: const Icon(Icons.clear,
                      color: Color(0xFF8E8E93), size: 18),
                )
              else
                const Icon(Icons.chevron_right,
                    color: Color(0xFF48484A), size: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showPathDialog(BuildContext context, String current) {
    final controller = TextEditingController(text: current);
    showCupertinoDialog<void>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Jalur Folder Lirik'),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: CupertinoTextField(
            controller: controller,
            placeholder: '/sdcard/Music/Lyrics',
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: const BoxDecoration(color: Color(0xFF2C2C2E)),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              AudioEffectsService.setLyricsPath(controller.text);
              Navigator.of(context).pop();
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }
}

// ─── TAMPILAN LIRIK (rows dalam settings page) ────────────────────────────────

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
              divisions: 48,
              onChanged: (v) {
                setState(() => temp = v);
              },
            )
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
