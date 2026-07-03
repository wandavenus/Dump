import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:musicplayer/widgets/common/scrolling_page_chrome.dart';

import '../../services/sleep_timer_service.dart';

part 'sleep_timer_page/page.dart';
part 'sleep_timer_page/body.dart';
part 'sleep_timer_page/active_card.dart';
part 'sleep_timer_page/presets.dart';

/// Shows the sleep timer picker as a bottom sheet.
/// Use this from the player 3-dot menu.
void showSleepTimerSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _SleepTimerSheetWidget(),
  );
}

class _SleepTimerSheetWidget extends StatefulWidget {
  const _SleepTimerSheetWidget();

  @override
  State<_SleepTimerSheetWidget> createState() =>
      _SleepTimerSheetWidgetState();
}

class _SleepTimerSheetWidgetState extends State<_SleepTimerSheetWidget> {
  /// Vertical offset (px) currently applied while the user drags the
  /// handle/header down to dismiss the sheet. Snaps back to 0 if the
  /// drag doesn't clear the dismiss threshold.
  double _dragOffset = 0;

  static const double _dismissDistanceThreshold = 80;
  static const double _dismissVelocityThreshold = 700;

  void _handleDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0;
    setState(() {
      _dragOffset = (_dragOffset + delta).clamp(0, double.infinity);
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (_dragOffset > _dismissDistanceThreshold ||
        velocity > _dismissVelocityThreshold) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _dragOffset = 0);
  }

  @override
  Widget build(BuildContext context) {
    final dragFraction = (_dragOffset / 240).clamp(0.0, 1.0);

    return Transform.translate(
      offset: Offset(0, _dragOffset),
      child: Opacity(
        opacity: 1 - (dragFraction * 0.35),
        child: Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(16),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle + header — swipe down here to dismiss.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: _handleDragUpdate,
                  onVerticalDragEnd: _handleDragEnd,
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
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            const Text(
                              'Sleep Timer',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            ValueListenableBuilder<bool>(
                              valueListenable: SleepTimerService.isActive,
                              builder:
                                  (_, active, _) =>
                                      active
                                          ? CupertinoButton(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            onPressed: () {
                                              SleepTimerService.cancel();
                                              Navigator.of(context).pop();
                                            },
                                            child: const Text(
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
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
                // Scrollable body — constrained to 65% of screen height
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.65,
                  ),
                  child: const _SleepTimerSheetBody(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Body variant for the bottom sheet — same structure as [_SleepTimerBody]
/// but preset taps also dismiss the sheet.
class _SleepTimerSheetBody extends StatelessWidget {
  const _SleepTimerSheetBody();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SleepTimerService.isActive,
      builder: (_, active, _) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          shrinkWrap: true,
          children: [
            if (active) ...[
              const _ActiveTimerCard(),
              const SizedBox(height: 24),
            ],
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'PILIH DURASI',
                style: TextStyle(
                  color: Color(0xFF8E8E93),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const _PresetList(dismissOnSelect: true),
          ],
        );
      },
    );
  }
}
