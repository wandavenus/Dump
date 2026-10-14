part of '../equalizer_page.dart';

// ─── EQ Presets ────────────────────────────────────────────────────────────────
//
// Native Cupertino sliding segmented control. The preset list stays horizontally
// scrollable because ten segments do not fit comfortably on a phone screen.

class _EqPresetChips extends StatelessWidget {
  const _EqPresetChips();

  @override
  Widget build(BuildContext context) {
    const presets = AudioEffectsService.eqPresets;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(context.l10n.preset),
        const SizedBox(height: 10),
        SizedBox(
          height: 38,
          child: ValueListenableBuilder<bool>(
            valueListenable: AudioEffectsService.equalizerEnabled,
            builder: (_, enabled, _) {
              return ValueListenableBuilder<int>(
                valueListenable: AudioEffectsService.eqPreset,
                builder: (_, currentPreset, _) {
                  final colors = AppColors.of(context);
                  final children = <int, Widget>{
                    for (var i = 0; i < presets.length; i++)
                      i: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          presets[i]['name'] as String,
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: currentPreset == i
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: currentPreset == i
                                ? Colors.white
                                : enabled
                                ? colors.primaryLabel
                                : colors.primaryLabel.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                  };

                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    physics: const ClampingScrollPhysics(),
                    child: CupertinoSlidingSegmentedControl<int>(
                      groupValue:
                          currentPreset >= 0 && currentPreset < presets.length
                          ? currentPreset
                          : null,
                      children: children,
                      onValueChanged: (index) {
                        if (enabled && index != null) {
                          unawaited(AudioEffectsService.applyEqPreset(index));
                        }
                      },
                      thumbColor: const Color(0xFFF92D48),
                      backgroundColor: colors.primaryLabel.withValues(
                        alpha: 0.08,
                      ),
                      padding: const EdgeInsets.all(3),
                    ),
                  );
                },
              );
            },
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}
