part of '../sleep_timer_page.dart';

class SleepTimerPage extends StatelessWidget {
  const SleepTimerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: FadingTitleAppBar(
        title: context.l10n.sleepTimerTitle,
        scrollOffset: 100,
        leading: CupertinoButton(
          padding: const EdgeInsets.only(left: 8),
          onPressed: () => Navigator.of(context).pop(),
          child: const Icon(
            CupertinoIcons.arrow_left,
            color: Color(0xFFF92D48),
            size: 28,
          ),
        ),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: SleepTimerService.isActive,
            builder:
                (_, active, _) =>
                    active
                        ? const CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: SleepTimerService.cancel,
                          child: Text(
                            context.l10n.cancelTimer,
                            style: const TextStyle(
                              color: Color(0xFFF92D48),
                              fontSize: 15,
                            ),
                          ),
                        )
                        : const SizedBox.shrink(),
          ),
        ],
      ),
      body: _SleepTimerBody(),
    );
  }
}
