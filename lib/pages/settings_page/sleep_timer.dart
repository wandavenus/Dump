part of '../settings_page.dart';

class _SleepTimerSection extends StatelessWidget {
  const _SleepTimerSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader('SLEEP TIMER'),
        const SizedBox(height: 6),
        ValueListenableBuilder<bool>(
          valueListenable: SleepTimerService.isActive,
          builder: (_, active, _) => ValueListenableBuilder<Duration?>(
            valueListenable: SleepTimerService.remaining,
            builder: (_, remaining, _) {
              String subtitle;
              if (!active) {
                subtitle = 'Nonaktif';
              } else if (remaining == null) {
                subtitle = 'Berhenti setelah lagu ini';
              } else {
                final m = remaining.inMinutes;
                final s = remaining.inSeconds % 60;
                subtitle = 'Sisa ${m}m ${s}s';
              }
              return SettingsActionRow(
                title: 'Sleep Timer',
                trailing: subtitle,
                onTap: () => Navigator.of(context).push(
                  CupertinoPageRoute<void>(
                    builder: (_) => const SleepTimerPage(),
                  ),
                ),
              );
            },
          ),
        ),
        const SettingsDivider(),
      ],
    );
  }
}

// ─── LIRIK ────────────────────────────────────────────────────────────────────
