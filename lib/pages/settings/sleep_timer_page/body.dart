part of '../sleep_timer_page.dart';

class _SleepTimerBody extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SleepTimerService.isActive,
      builder: (_, active, _) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (active) ...[
              const _ActiveTimerCard(),
              const SizedBox(height: 24),
            ],
            Padding(
              padding: const EdgeInsets.only(left: 0, bottom: 8),
              child: Text(
                 context.l10n.sleepPresetSection,
                style: TextStyle(
                  color: AppColors.of(context).secondaryLabel,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const _PresetList(),
          ],
        );
      },
    );
  }
}

// ─── Active timer card ────────────────────────────────────────────────────────
