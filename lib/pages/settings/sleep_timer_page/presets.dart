part of '../sleep_timer_page.dart';

class _PresetList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: List.generate(SleepTimerService.presets.length, (i) {
          final preset = SleepTimerService.presets[i];
          final isLast = i == SleepTimerService.presets.length - 1;
          return Column(
            children: [
              InkWell(
                borderRadius: isLast
                    ? const BorderRadius.vertical(bottom: Radius.circular(12))
                    : BorderRadius.zero,
                onTap: () => _startPreset(context, preset),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Icon(
                        preset.duration == null
                            ? Icons.music_note
                            : Icons.timer,
                        color: const Color(0xFF8E8E93),
                        size: 20,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          preset.label,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 16),
                        ),
                      ),
                      const Icon(Icons.chevron_right,
                          color: Color(0xFF48484A), size: 20),
                    ],
                  ),
                ),
              ),
              if (!isLast)
                const Divider(
                  height: 0.5,
                  thickness: 0.5,
                  color: Color(0xFF38383A),
                  indent: 50,
                ),
            ],
          );
        }),
      ),
    );
  }

  void _startPreset(
      BuildContext context,
      ({String label, Duration? duration}) preset) {
    if (preset.duration == null) {
      SleepTimerService.startEndOfSong();
    } else {
      SleepTimerService.startDuration(preset.duration!);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          preset.duration == null
              ? 'Timer: berhenti setelah lagu ini'
              : 'Timer: ${preset.label}',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF1C1C1E),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
