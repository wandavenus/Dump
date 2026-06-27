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
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReverbPickerSheet(current: preset),
    );
  }
}

class _ReverbPickerSheet extends StatelessWidget {
  const _ReverbPickerSheet({required this.current});
  final int current;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Reverb',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          ...List.generate(
            AudioEffectsService.reverbPresetNames.length,
            (i) => _ReverbOption(
              name: AudioEffectsService.reverbPresetNames[i],
              index: i,
              selected: i == current,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _ReverbOption extends StatelessWidget {
  const _ReverbOption({
    required this.name,
    required this.index,
    required this.selected,
  });
  final String name;
  final int index;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? const Color(0xFFFC3C44) : Colors.white30,
            width: 2,
          ),
          color: selected ? const Color(0xFFFC3C44) : Colors.transparent,
        ),
        child: selected
            ? const Icon(Icons.check, size: 14, color: Colors.white)
            : null,
      ),
      title: Text(
        name,
        style: TextStyle(
          color: selected ? const Color(0xFFFC3C44) : Colors.white,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          fontSize: 15,
        ),
      ),
      onTap: () {
        AudioEffectsService.setReverb(index);
        Navigator.pop(context);
      },
    );
  }
}

// ─── SPATIAL AUDIO ────────────────────────────────────────────────────────────
