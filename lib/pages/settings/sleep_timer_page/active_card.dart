part of '../sleep_timer_page.dart';

class _ActiveTimerCard extends StatelessWidget {
  const _ActiveTimerCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFF92D48).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.bedtime, color: Color(0xFFF92D48), size: 18),
              SizedBox(width: 8),
              Text(
                'Sleep Timer Aktif',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<Duration?>(
            valueListenable: SleepTimerService.remaining,
            builder: (_, remaining, _) {
              if (remaining == null) {
                return const Text(
                  'Berhenti setelah lagu ini selesai',
                  style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14),
                );
              }
              final h = remaining.inHours;
              final m = remaining.inMinutes % 60;
              final s = remaining.inSeconds % 60;
              final label =
                  h > 0
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
          ),
          const SizedBox(height: 8),
          const Text(
            'Musik akan fade out perlahan saat timer habis',
            style: TextStyle(color: Color(0xFF636366), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ─── Preset list ──────────────────────────────────────────────────────────────
