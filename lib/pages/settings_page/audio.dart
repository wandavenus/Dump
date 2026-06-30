part of '../settings_page.dart';

class _AudioSection extends StatelessWidget {
  const _AudioSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader('AUDIO'),
        const SizedBox(height: 6),

        // ── ReplayGain ──────────────────────────────────────────────────────
        const _ReplayGainSection(),
        const SettingsDivider(),

        // ── Legacy Normalize ────────────────────────────────────────────────
        ValueListenableBuilder<bool>(
          valueListenable: AudioEffectsService.audioNormalize,
          builder: (_, v, _) => SettingsToggleRow(
            title: 'Audio Normalize',
            subtitle: 'Boost volume rendah',
            value: v,
            onChanged: AudioEffectsService.setNormalize,
          ),
        ),
        const SettingsDivider(),

        const _CrossfadePicker(),
        const SettingsDivider(),

        ValueListenableBuilder<double>(
          valueListenable: AudioEffectsService.playbackSpeed,
          builder: (_, v, _) => SettingsSliderRow(
            title: 'Kecepatan Putar',
            subtitle: '${v.toStringAsFixed(2)}x',
            value: v,
            min: 0.25,
            max: 3.0,
            onChanged: AudioEffectsService.setSpeed,
            divisions: 22,
            showReset: v != 1.0,
            onReset: () => AudioEffectsService.setSpeed(1.0),
          ),
        ),
        const SettingsDivider(),

        ValueListenableBuilder<double>(
          valueListenable: AudioEffectsService.pitchShift,
          builder: (_, v, _) => SettingsSliderRow(
            title: 'Pitch Shift',
            subtitle: v == 0
                ? 'Normal'
                : '${v > 0 ? '+' : ''}${v.toStringAsFixed(1)} semitone',
            value: v,
            min: -6,
            max: 6,
            onChanged: AudioEffectsService.setPitch,
            divisions: 24,
            showReset: v != 0,
            onReset: () => AudioEffectsService.setPitch(0),
          ),
        ),
        const SettingsDivider(),

        ValueListenableBuilder<int>(
          valueListenable: AudioEffectsService.bassBoost,
          builder: (_, v, _) => SettingsSliderRow(
            title: 'Bass Boost',
            subtitle: v == 0
                ? 'Nonaktif'
                : AudioEngine.bassBoostSupported
                    ? '${(v / 10).round()}%'
                    : 'Tidak didukung perangkat ini',
            value: v.toDouble(),
            min: 0,
            max: 1000,
            onChanged: (val) => AudioEffectsService.setBassBoost(val.round()),
            divisions: 20,
            showReset: v != 0,
            onReset: () => AudioEffectsService.setBassBoost(0),
          ),
        ),
        const SettingsDivider(),
      ],
    );
  }
}

// ── ReplayGain Section ─────────────────────────────────────────────────────

class _ReplayGainSection extends StatelessWidget {
  const _ReplayGainSection();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ReplayGainMode>(
      valueListenable: AudioEffectsService.replayGainMode,
      builder: (context, mode, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Mode selector
            SettingsActionRow(
              title: 'ReplayGain',
              trailing: mode.label,
              onTap: () => _showModePicker(context, mode),
            ),
            if (mode != ReplayGainMode.off)
              Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 6),
                child: Text(
                  mode.description,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),

            // Preamp slider — only visible when RG is active
            if (mode != ReplayGainMode.off) ...[
              const SizedBox(height: 4),
              ValueListenableBuilder<double>(
                valueListenable: AudioEffectsService.replayGainPreamp,
                builder: (_, preamp, _) => SettingsSliderRow(
                  title: 'Preamp',
                  subtitle: preamp == 0
                      ? '0 dB'
                      : '${preamp > 0 ? '+' : ''}${preamp.toStringAsFixed(1)} dB',
                  value: preamp,
                  min: -15,
                  max: 15,
                  onChanged: AudioEffectsService.setReplayGainPreamp,
                  divisions: 30,
                  showReset: preamp != 0,
                  onReset: () => AudioEffectsService.setReplayGainPreamp(0),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  void _showModePicker(BuildContext context, ReplayGainMode current) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReplayGainModePicker(current: current),
    );
  }
}

// ignore: unused_element
class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.mode});
  final ReplayGainMode mode;

  @override
  Widget build(BuildContext context) {
    final active = mode != ReplayGainMode.off;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: active
            ? const Color(0xFFFC3C44).withAlpha(30)
            : Colors.white.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active
              ? const Color(0xFFFC3C44).withAlpha(120)
              : Colors.white.withAlpha(30),
          width: 0.8,
        ),
      ),
      child: Text(
        mode.label,
        style: TextStyle(
          fontSize: 12,
          color: active ? const Color(0xFFFC3C44) : Colors.white60,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _ReplayGainModePicker extends StatelessWidget {
  const _ReplayGainModePicker({required this.current});
  final ReplayGainMode current;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(16),
      ),
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
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Mode ReplayGain',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          ...ReplayGainMode.values.map(
            (mode) => _ModeOption(mode: mode, selected: mode == current),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({required this.mode, required this.selected});
  final ReplayGainMode mode;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? const Color(0xFFFC3C44) : Colors.white30,
            width: 2,
          ),
          color: selected ? const Color(0xFFFC3C44) : Colors.transparent,
        ),
        child: selected
            ? const Icon(Icons.check, size: 14, color: Colors.white)
            : null,
      ),
      title: Text(
        mode.label,
        style: TextStyle(
          color: selected ? const Color(0xFFFC3C44) : Colors.white,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          fontSize: 15,
        ),
      ),
      subtitle: Text(
        mode.description,
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
      onTap: () {
        AudioEffectsService.setReplayGainMode(mode);
        Navigator.pop(context);
      },
    );
  }
}

// ─── Crossfade discrete picker ────────────────────────────────────────────────

class _CrossfadePicker extends StatelessWidget {
  const _CrossfadePicker();

  static const _steps = [0.0, 1.0, 2.0, 4.0, 6.0, 8.0, 12.0];
  static const _labels = ['Off', '1s', '2s', '4s', '6s', '8s', '12s'];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: AudioEffectsService.crossfadeDuration,
      builder: (_, current, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Crossfade',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    current == 0
                        ? 'Nonaktif'
                        : '${current.toStringAsFixed(0)} detik',
                    style: const TextStyle(
                        color: Color(0xFF8E8E93), fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: List.generate(_steps.length, (i) {
                  final active = current == _steps[i];
                  final isLast = i == _steps.length - 1;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () =>
                          AudioEffectsService.setCrossfade(_steps[i]),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: isLast
                            ? EdgeInsets.zero
                            : const EdgeInsets.only(right: 5),
                        height: 36,
                        decoration: BoxDecoration(
                          color: active
                              ? const Color(0xFFF92D48)
                              : Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _labels[i],
                          style: TextStyle(
                            color: active ? Colors.white : Colors.white54,
                            fontWeight: active
                                ? FontWeight.w600
                                : FontWeight.w400,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }
}
