part of '../settings_page.dart';

/// Root audio settings section. Composes all audio sub-sections.
class _AudioSection extends StatelessWidget {
  const _AudioSection();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionHeader(l.sectionAudio),
        const SizedBox(height: 6),

        BitPerfectLock(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _ReplayGainSection(),
              const SettingsDivider(),

              const _LoudnessNormSection(),
              const SettingsDivider(),

              const _CrossfeedSection(),
              const SettingsDivider(),

              const _CrossfadePicker(),
              const SettingsDivider(),

              ValueListenableBuilder<bool>(
                valueListenable: MediaCapabilitiesService.stereoWideningEnabled,
                builder: (_, enabled, _) => ValueListenableBuilder<double>(
                  valueListenable:
                      MediaCapabilitiesService.stereoWideningStrength,
                  builder: (_, v, _) {
                    final pct = (v * 100).round();
                    return SettingsSliderRow(
                      title: l.stereoWidening,
                      subtitle: enabled ? '$pct%' : l.disabled,
                      value: enabled ? v : 0.0,
                      min: 0.0,
                      max: 1.0,
                      divisions: 20,
                      onChanged: (val) async {
                        if (val > 0) {
                          await MediaCapabilitiesService.setStereoWidening(
                            true,
                          );
                          await MediaCapabilitiesService.setStereoWideningStrength(
                            val,
                          );
                        } else {
                          await MediaCapabilitiesService.setStereoWidening(
                            false,
                          );
                        }
                      },
                      showReset: enabled,
                      onReset: () async {
                        await MediaCapabilitiesService.setStereoWidening(false);
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
