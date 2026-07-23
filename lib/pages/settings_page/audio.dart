part of '../settings_page.dart';

// Sub-sections extracted to settings_page/audio/:
//   audio/replaygain_section.dart  — _ReplayGainSection, _ModeChip,
//                                    _ReplayGainModePicker, _ModeOption
//   audio/loudness_section.dart    — _LoudnessNormSection
//   audio/crossfeed_section.dart   — _CrossfeedSection
//   audio/crossfade_picker.dart    — _CrossfadePicker
//   audio/batch_scan_section.dart  — _BatchScanSection, _ScanIdleRow,
//                                    _ScanProgressRow, _ScanResultRow

/// Root audio settings section. Composes all audio sub-sections.
class _AudioSection extends StatelessWidget {
  const _AudioSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader('AUDIO'),
        const SizedBox(height: 6),

        BitPerfectLock(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Audio Normalize ─────────────────────────────────────────────
              const _ReplayGainSection(),
              const SettingsDivider(),

              // ── Loudness Normalization ──────────────────────────────────────
              const _LoudnessNormSection(),
              const SettingsDivider(),

              // ── Crossfeed ───────────────────────────────────────────────────
              const _CrossfeedSection(),
              const SettingsDivider(),

              // ── Crossfade ───────────────────────────────────────────────────
              const _CrossfadePicker(),
              const SettingsDivider(),

              // ── Stereo Widening ─────────────────────────────────────────────
              ValueListenableBuilder<bool>(
                valueListenable:
                    MediaCapabilitiesService.stereoWideningEnabled,
                builder: (_, enabled, _) =>
                    ValueListenableBuilder<double>(
                  valueListenable:
                      MediaCapabilitiesService.stereoWideningStrength,
                  builder: (_, v, _) {
                    final pct = (v * 100).round();
                    return SettingsSliderRow(
                      title:    'Stereo Widening',
                      subtitle: enabled ? '$pct%' : 'Nonaktif',
                      value:    enabled ? v : 0.0,
                      min:      0.0,
                      max:      1.0,
                      divisions: 20,
                      onChanged: (val) async {
                        if (val > 0) {
                          await MediaCapabilitiesService
                              .setStereoWidening(true);
                          await MediaCapabilitiesService
                              .setStereoWideningStrength(val);
                        } else {
                          await MediaCapabilitiesService
                              .setStereoWidening(false);
                        }
                      },
                      showReset: enabled,
                      onReset: () async {
                        await MediaCapabilitiesService
                            .setStereoWidening(false);
                      },
                      expandable: true,
                    );
                  },
                ),
              ),
              const SettingsDivider(),
            ],
          ),
        ),
      ],
    );
  }
}
