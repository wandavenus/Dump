part of '../settings_page.dart';

class _AudioOutputRow extends StatelessWidget {
  final int mode;
  const _AudioOutputRow({required this.mode});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _showPicker(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            const Icon(Icons.settings_input_component,
                color: Color(0xFF8E8E93), size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Output Audio',
                      style: TextStyle(color: Colors.white, fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(
                    AudioEffectsService.audioOutputNames[mode.clamp(0, 2).toInt()],
                    style: const TextStyle(
                        color: Color(0xFF8E8E93), fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: Color(0xFF48484A), size: 20),
          ],
        ),
      ),
    );
  }

  void _showPicker(BuildContext context) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('Jalur Audio Output'),
        message: const Text(
            'AAudio direkomendasikan untuk Android 8+.\n'
            'Hi-Res Audio mengaktifkan DAC hardware (perlu headset hi-res).'),
        actions: List.generate(
          AudioEffectsService.audioOutputNames.length,
          (i) => CupertinoActionSheetAction(
            isDefaultAction: i == mode,
            onPressed: () {
              AudioEffectsService.setAudioOutputMode(i);
              Navigator.of(context).pop();
              if (i == 2) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Hi-Res: Pastikan headset hi-res terhubung. '
                        'Di MIUI: Pengaturan → Suara → HiFi Audio.'),
                    backgroundColor: Color(0xFF1C1C1E),
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(seconds: 5),
                  ),
                );
              }
            },
            child: Text(AudioEffectsService.audioOutputNames[i]),
          ),
        ),
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
      ),
    );
  }
}

// ─── SISTEM ───────────────────────────────────────────────────────────────────
