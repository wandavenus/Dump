part of '../../settings_page.dart';

// ─── Crossfeed section ──────────────────────────────────────────────────────
//
// Frequency-dependent headphone crossfeed (Phase 7, native DSP pipeline).
// Blends a lowpass-filtered version of each channel into the opposite
// channel — reduces the unnatural hard-panned isolation of headphone
// listening by mimicking the acoustic crosstalk of speakers.

class _CrossfeedSection extends StatelessWidget {
  const _CrossfeedSection();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AudioEffectsService.crossfeedEnabled,
      builder: (context, enabled, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsToggleRow(
              title:    'Crossfeed',
              subtitle: enabled
                  ? 'Simulasikan pencampuran kanal seperti speaker di headphone'
                  : 'Aktifkan untuk headphone terasa lebih natural',
              value:     enabled,
              onChanged: AudioEffectsService.setCrossfeedEnabled,
            ),
            if (enabled) ...[
              const SizedBox(height: 2),
              ValueListenableBuilder<double>(
                valueListenable: AudioEffectsService.crossfeedAmount,
                builder: (_, amount, _) => SettingsSliderRow(
                  title:     'Kekuatan',
                  subtitle:  '${(amount * 100).round()}%',
                  value:     amount,
                  min:       0.0,
                  max:       1.0,
                  onChanged: AudioEffectsService.setCrossfeedAmount,
                  divisions: 20,
                  showReset: amount != 0.3,
                  onReset: () =>
                      AudioEffectsService.setCrossfeedAmount(0.3),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
