part of '../sleep_timer_page.dart';

class _PresetList extends StatelessWidget {
  /// Dismiss the bottom sheet after selecting a preset.
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

    if (dismissOnSelect && context.mounted) {
      Navigator.of(context).pop();
    }
  }
}
