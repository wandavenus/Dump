part of '../settings_page.dart';

class _ReverbRow extends StatelessWidget {
  final int preset;
  const _ReverbRow({required this.preset});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _showReverbPicker(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Reverb',
                      style: TextStyle(color: Colors.white, fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(
                    AudioEngine.reverbSupported
                        ? AudioEffectsService.reverbPresetNames[preset]
                        : 'Tidak didukung perangkat ini',
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

  void _showReverbPicker(BuildContext context) {
    if (!AudioEngine.reverbSupported) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Reverb tidak didukung di perangkat ini'),
        backgroundColor: Color(0xFF1C1C1E),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('Reverb'),
        actions: List.generate(
          AudioEffectsService.reverbPresetNames.length,
          (i) => CupertinoActionSheetAction(
            isDefaultAction: i == preset,
            onPressed: () {
              AudioEffectsService.setReverb(i);
              Navigator.of(context).pop();
            },
            child: Text(AudioEffectsService.reverbPresetNames[i]),
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

// ─── SPATIAL AUDIO ────────────────────────────────────────────────────────────
