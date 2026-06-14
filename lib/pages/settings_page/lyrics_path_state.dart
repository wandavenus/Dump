part of '../settings_page.dart';

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
