part of '../settings_page.dart';

// ─── Lyrics appearance picker functions ───────────────────────────────────────
// Library-level helpers shared by _LyricsAppearanceRows.
// Extracted from lyrics_rows.dart to keep that file concise.

void _lyricPickFontSize(BuildContext ctx, double cur) {
  showCupertinoModalPopup<void>(
    context: ctx,
    builder: (_) => CupertinoActionSheet(
      title: const Text('Ukuran Teks Lirik'),
      actions: [
        for (final s in [
          (label: 'Kecil (S)',          value: 14.0),
          (label: 'Sedang (M)',         value: 18.0),
          (label: 'Besar (L)',          value: 22.0),
          (label: 'Sangat Besar (XL)',  value: 26.0),
          (label: 'Kustom...',          value: -1.0),
        ])
          CupertinoActionSheetAction(
            isDefaultAction: cur == s.value,
            onPressed: () {
              if (s.value == -1.0) {
                Navigator.pop(ctx);
                _lyricShowCustomFontSize(ctx);
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

void _lyricShowCustomFontSize(BuildContext context) {
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
              onChanged: (v) => setState(() => temp = v),
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

void _lyricPickAlign(BuildContext ctx, String cur) {
  showCupertinoModalPopup<void>(
    context: ctx,
    builder: (_) => CupertinoActionSheet(
      title: const Text('Rata Teks Lirik'),
      actions: [
        for (final o in [
          (label: 'Kiri',   value: 'left'),
          (label: 'Tengah', value: 'center'),
          (label: 'Kanan',  value: 'right'),
        ])
          CupertinoActionSheetAction(
            isDefaultAction: cur == o.value,
            onPressed: () {
              LyricsSettings.setTextAlign(o.value);
              Navigator.pop(ctx);
            },
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

void _lyricPickColor(BuildContext ctx, String cur) {
  showCupertinoModalPopup<void>(
    context: ctx,
    builder: (_) => CupertinoActionSheet(
      title: const Text('Warna Teks Aktif'),
      actions: [
        for (final o in [
          (label: 'Putih',  value: 'white'),
          (label: 'Merah',  value: 'accent'),
          (label: 'Kuning', value: 'yellow'),
        ])
          CupertinoActionSheetAction(
            isDefaultAction: cur == o.value,
            onPressed: () {
              LyricsSettings.setActiveColor(o.value);
              Navigator.pop(ctx);
            },
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
