// ── SleepTimerPage library ────────────────────────────────────────────────────
//
// Library entry point for the sleep timer bottom sheet.
// Declares shared imports and includes sub-parts via `part`.
//
// Public surface: [showSleepTimerSheet] (top-level helper used by the player
// 3-dot menu); widget tree lives in the `sleep_timer_page/` sub-parts.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:musicplayer/extensions/localization_extension.dart';
import 'package:musicplayer/theme/app_colors.dart';
import 'package:musicplayer/widgets/common/scrolling_page_chrome.dart';
import 'package:musicplayer/widgets/common/swipe_to_dismiss_sheet.dart';

import '../../services/sleep_timer_service.dart';

part 'sleep_timer_page/page.dart';
part 'sleep_timer_page/body.dart';
part 'sleep_timer_page/active_card.dart';
part 'sleep_timer_page/presets.dart';

/// Shows the sleep timer picker as a bottom sheet.
/// Use this from the player 3-dot menu.
void showSleepTimerSheet(BuildContext context) {
  unawaited(showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _SleepTimerSheetWidget(),
  ));
}

class _SleepTimerSheetWidget extends StatelessWidget {
  const _SleepTimerSheetWidget();

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return SwipeToDismissSheet(
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: c.dragHandle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text(
                       context.l10n.sleepTimerTitle,
                      style: TextStyle(
                        color: c.primaryLabel,
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
                                     child: Text(
                                       context.l10n.cancelTimer,
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
              // Body — constrained to 65% of screen height. Presets fit
              // within the constraint, so the whole card can safely
              // respond to swipe-to-dismiss drags.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.65,
                ),
                child: const _SleepTimerSheetBody(),
              ),
            ],
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
    final c = AppColors.of(context);
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
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(
                 context.l10n.sleepPresetSection,
                style: TextStyle(
                  color: c.secondaryLabel,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const _PresetList(dismissOnSelect: false),
          ],
        );
      },
    );
  }
}
