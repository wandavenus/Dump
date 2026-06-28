part of '../sleep_timer_page.dart';

class SleepTimerPage extends StatelessWidget {
  const SleepTimerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: FadingTitleAppBar(
        title: 'Sleep Timer',
        scrollOffset: 100,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
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
                            'Batalkan',
                            style: TextStyle(
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
