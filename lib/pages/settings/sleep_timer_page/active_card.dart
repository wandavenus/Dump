part of '../sleep_timer_page.dart';

class _ActiveTimerCard extends StatelessWidget {
  const _ActiveTimerCard();

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFF92D48).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.bedtime, color: Color(0xFFF92D48), size: 18),
              const SizedBox(width: 8),
              Text(
                context.l10n.sleepTimerActive,
                style: TextStyle(
                  color: c.primaryLabel,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<bool>(
            valueListenable: SleepTimerService.isFading,
            builder: (_, fading, _) {
              if (fading) {
                // Fade-out in progress (timer already fired) — show a
                // cancellable state instead of a frozen 00:00 countdown.
                return Text(
                  context.l10n.sleepFadingOut,
                  style: const TextStyle(
                    color: Color(0xFFF92D48),
                    fontSize: 26,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 1,
                  ),
                );
              }
              return ValueListenableBuilder<Duration?>(
                valueListenable: SleepTimerService.remaining,
                builder: (_, remaining, _) {
                  if (remaining == null) {
                    return Text(
                      context.l10n.sleepAfterSong,
                      style: TextStyle(color: c.secondaryLabel, fontSize: 14),
                    );
                  }
                  final h = remaining.inHours;
                  final m = remaining.inMinutes % 60;
                  final s = remaining.inSeconds % 60;
                  final label = h > 0
                      ? '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
                      : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
                  return Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFFF92D48),
                      fontSize: 40,
                      fontWeight: FontWeight.w200,
                      letterSpacing: 2,
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.sleepFadeOut,
            style: TextStyle(color: c.tertiaryLabel, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ─── Preset list ──────────────────────────────────────────────────────────────
