part of '../sleep_timer_page.dart';

class _PresetList extends StatelessWidget {
  /// When true (bottom-sheet mode), dismiss the sheet after selecting a preset.
  final bool dismissOnSelect;

  const _PresetList({this.dismissOnSelect = false});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
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
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        preset.duration == null
                            ? Icons.music_note
                            : Icons.timer,
                        color: c.secondaryLabel,
                        size: 20,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          _localizedPresetLabel(context, preset),
                          style: TextStyle(color: c.primaryLabel, fontSize: 16),
                        ),
                      ),
                      Icon(Icons.chevron_right, color: c.separator, size: 20),
                    ],
                  ),
                ),
              ),
              if (!isLast)
                Divider(
                  height: 0.5,
                  thickness: 0.5,
                  color: c.subtleSeparator,
                  indent: 50,
                ),
            ],
          );
        }),
      ),
    );
  }

  String _localizedPresetLabel(
    BuildContext context,
    ({Duration? duration}) preset,
  ) {
    final duration = preset.duration;
    if (duration == null) return context.l10n.sleepPresetEndOfSong;
    if (duration.inMinutes < 60) {
      return context.l10n.sleepPresetMinutes(duration.inMinutes);
    }
    final hours = duration.inMinutes / 60;
    final hourLabel = hours == hours.roundToDouble()
        ? hours.toInt().toString()
        : hours.toString().replaceFirst('.', ',');
    return context.l10n.sleepPresetHour(hourLabel);
  }

  void _startPreset(BuildContext context, ({Duration? duration}) preset) {
    if (preset.duration == null) {
      SleepTimerService.startEndOfSong();
    } else {
      SleepTimerService.startDuration(preset.duration!);
    }

    if (dismissOnSelect) {
      Navigator.of(context).pop();
      return;
    }

    final c = AppColors.of(context);
    final label = _localizedPresetLabel(context, preset);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          preset.duration == null
              ? context.l10n.timerAfterSong
              : context.l10n.timerDuration(label),
          style: TextStyle(color: c.primaryLabel),
        ),
        backgroundColor: c.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
