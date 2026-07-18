part of '../settings_page.dart';

// TODO(refactor): audio.dart is 869 lines — god file. Future split boundaries:
//   1. _ReplayGainSection → audio/replaygain_section.dart
//   2. _LoudnessNormSection → audio/loudness_section.dart
//   3. _EqualizerSection → audio/equalizer_section.dart
//   4. _OutputModeSection → audio/output_mode_section.dart
//   5. _DspSection (compressor/limiter/crossfeed) → audio/dsp_section.dart

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
              // ── Audio Normalize ───────────────────────────────────────────
              const _ReplayGainSection(),
              const SettingsDivider(),

              // ── Loudness Normalization ─────────────────────────────────────
              const _LoudnessNormSection(),
              const SettingsDivider(),

              // ── Crossfeed ───────────────────────────────────────────────────
              const _CrossfeedSection(),
              const SettingsDivider(),

              const _CrossfadePicker(),
              const SettingsDivider(),

              // ── Stereo Widening ───────────────────────────────────────────
              ValueListenableBuilder<bool>(
                valueListenable:
                    MediaCapabilitiesService.stereoWideningEnabled,
                builder: (_, enabled, _) => ValueListenableBuilder<double>(
                  valueListenable:
                      MediaCapabilitiesService.stereoWideningStrength,
                  builder: (_, v, _) {
                    final pct = (v * 100).round();
                    return SettingsSliderRow(
                      title: 'Stereo Widening',
                      subtitle: enabled ? '$pct%' : 'Nonaktif',
                      value: enabled ? v : 0.0,
                      min: 0.0,
                      max: 1.0,
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

// ── ReplayGain Section ─────────────────────────────────────────────────────

class _ReplayGainSection extends StatefulWidget {
  const _ReplayGainSection();

  @override
  State<_ReplayGainSection> createState() => _ReplayGainSectionState();
}

class _ReplayGainSectionState extends State<_ReplayGainSection>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _ctrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _expanded ? _ctrl.forward() : _ctrl.reverse();
  }

  void _showModePicker(BuildContext context, ReplayGainMode current) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReplayGainModePicker(current: current),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ReplayGainMode>(
      valueListenable: AudioEffectsService.replayGainMode,
      builder: (context, mode, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header — selalu terlihat, bisa diketuk
            InkWell(
              onTap: _toggle,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                child: Row(
                  children: [
                    const Text(
                      'Audio Normalize',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        mode.label,
                        style: const TextStyle(
                            color: Color(0xFF8E8E93), fontSize: 13),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 220),
                      child: const Icon(Icons.keyboard_arrow_down,
                          color: Colors.white38, size: 18),
                    ),
                  ],
                ),
              ),
            ),

            // Konten collapsible
            SizeTransition(
              sizeFactor: _ctrl,
              alignment: Alignment.topCenter,
              child: FadeTransition(
                opacity: _fade,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Mode picker row
                    InkWell(
                      onTap: () => _showModePicker(context, mode),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Mode',
                                      style: TextStyle(
                                          color: Colors.white, fontSize: 15)),
                                  const SizedBox(height: 2),
                                  Text(mode.label,
                                      style: const TextStyle(
                                          color: Color(0xFF8E8E93),
                                          fontSize: 12)),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right,
                                color: Colors.white38, size: 18),
                          ],
                        ),
                      ),
                    ),

                    // Deskripsi mode aktif
                    if (mode != ReplayGainMode.off)
                      Padding(
                        padding:
                            const EdgeInsets.only(left: 16, bottom: 6),
                        child: Text(
                          mode.description,
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 12),
                        ),
                      ),

                    // Preamp slider + clipping protection — hanya saat mode aktif
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
                          onReset: () =>
                              AudioEffectsService.setReplayGainPreamp(0),
                        ),
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: AudioEffectsService.clippingProtection,
                        builder: (_, clip, _) => SettingsToggleRow(
                          title: 'Clipping Protection',
                          subtitle: 'Cegah distorsi saat gain melebihi 0 dBFS',
                          value: clip,
                          onChanged: AudioEffectsService.setClippingProtection,
                        ),
                      ),
                    ],
                    const _BatchScanSection(),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
          ],
        );
      },
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
            ? const Color(0xFFF92D48).withAlpha(30)
            : Colors.white.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active
              ? const Color(0xFFF92D48).withAlpha(120)
              : Colors.white.withAlpha(30),
          width: 0.8,
        ),
      ),
      child: Text(
        mode.label,
        style: TextStyle(
          fontSize: 12,
          color: active ? const Color(0xFFF92D48) : Colors.white60,
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
    return SwipeToDismissSheet(
      child: Container(
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
                  'Mode Audio Normalize',
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
            color: selected ? const Color(0xFFF92D48) : Colors.white30,
            width: 2,
          ),
          color: selected ? const Color(0xFFF92D48) : Colors.transparent,
        ),
        child: selected
            ? const Icon(Icons.check, size: 14, color: Colors.white)
            : null,
      ),
      title: Text(
        mode.label,
        style: TextStyle(
          color: selected ? const Color(0xFFF92D48) : Colors.white,
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

// ─── Loudness Normalization section ───────────────────────────────────────────

class _LoudnessNormSection extends StatelessWidget {
  const _LoudnessNormSection();

  static const _lufsTargets = <double>[-14.0, -16.0, -18.0, -23.0];
  static const _lufsLabels  = ['-14 LUFS', '-16 LUFS', '-18 LUFS', '-23 LUFS'];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AudioEffectsService.loudnessNormEnabled,
      builder: (context, enabled, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsToggleRow(
              title: 'Loudness Normalization',
              subtitle: enabled
                  ? 'Menyamakan kenyaringan secara real-time (EBU R128)'
                  : 'Normalisasi kenyaringan saat diputar',
              value: enabled,
              onChanged: AudioEffectsService.setLoudnessNormEnabled,
            ),
            if (enabled) ...[
              const SizedBox(height: 2),
              ValueListenableBuilder<double>(
                valueListenable: AudioEffectsService.loudnessNormTarget,
                builder: (context, target, _) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Target: ${target.toStringAsFixed(1)} LUFS',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 6),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: List.generate(_lufsTargets.length, (i) {
                              final selected =
                                  (target - _lufsTargets[i]).abs() < 0.1;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(_lufsLabels[i]),
                                  selected: selected,
                                  onSelected: (_) {
                                    AudioEffectsService.setLoudnessNormTarget(
                                        _lufsTargets[i]);
                                  },
                                ),
                              );
                            }),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Streaming −14, Podcast −16, Broadcast −23',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withAlpha(160),
                              ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ],
        );
      },
    );
  }
}

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
              title: 'Crossfeed',
              subtitle: enabled
                  ? 'Simulasikan pencampuran kanal seperti speaker di headphone'
                  : 'Aktifkan untuk headphone terasa lebih natural',
              value: enabled,
              onChanged: AudioEffectsService.setCrossfeedEnabled,
            ),
            if (enabled) ...[
              const SizedBox(height: 2),
              ValueListenableBuilder<double>(
                valueListenable: AudioEffectsService.crossfeedAmount,
                builder: (_, amount, _) => SettingsSliderRow(
                  title: 'Kekuatan',
                  subtitle: '${(amount * 100).round()}%',
                  value: amount,
                  min: 0.0,
                  max: 1.0,
                  onChanged: AudioEffectsService.setCrossfeedAmount,
                  divisions: 20,
                  showReset: amount != 0.3,
                  onReset: () => AudioEffectsService.setCrossfeedAmount(0.3),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

// ─── Compressor section ─────────────────────────────────────────────────────
//
// Feed-forward soft-knee compressor (Phase 6, native DSP pipeline). Reduces
// dynamic range above a threshold — evens out loud/quiet passages.

// ─── Crossfade discrete picker ────────────────────────────────────────────────

class _CrossfadePicker extends StatefulWidget {
  const _CrossfadePicker();

  @override
  State<_CrossfadePicker> createState() => _CrossfadePickerState();
}

class _CrossfadePickerState extends State<_CrossfadePicker>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _ctrl;
  late final Animation<double> _fade;

  static const _steps  = [0.0, 1.0, 2.0, 4.0, 6.0, 8.0, 12.0];
  static const _labels = ['Off', '1s', '2s', '4s', '6s', '8s', '12s'];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _expanded ? _ctrl.forward() : _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: AudioEffectsService.crossfadeDuration,
      builder: (_, current, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              InkWell(
                onTap: _toggle,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  child: Row(
                    children: [
                      const Text('Crossfade',
                          style:
                              TextStyle(color: Colors.white, fontSize: 16)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          current == 0
                              ? 'Nonaktif'
                              : '${current.toStringAsFixed(0)} detik',
                          style: const TextStyle(
                              color: Color(0xFF8E8E93), fontSize: 13),
                        ),
                      ),
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 220),
                        child: const Icon(Icons.keyboard_arrow_down,
                            color: Colors.white38, size: 18),
                      ),
                    ],
                  ),
                ),
              ),

              // Konten collapsible — tombol durasi
              SizeTransition(
                sizeFactor: _ctrl,
                alignment: Alignment.topCenter,
                child: FadeTransition(
                  opacity: _fade,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
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
                                  color: active
                                      ? Colors.white
                                      : Colors.white54,
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
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Batch ReplayGain Scan section ────────────────────────────────────────────
//
// Sits inside the _ReplayGainSection collapsible area.
// Shows an action row (idle), progress indicator (scanning), or a brief result
// summary (finished).  The actual scan runs as a background Future so the UI
// stays responsive while MediaCodec decodes each file.

class _BatchScanSection extends StatefulWidget {
  const _BatchScanSection();

  @override
  State<_BatchScanSection> createState() => _BatchScanSectionState();
}

class _BatchScanSectionState extends State<_BatchScanSection> {
  Future<void> _startScan(BuildContext context) async {
    try {
      final songs = await MediaStoreService.getSongs();
      if (!context.mounted) return;
      if (songs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tidak ada lagu ditemukan di library.')),
        );
        return;
      }
      // Tulis tag ke file secara otomatis setelah scan — tidak perlu
      // konfirmasi manual dari user.
      unawaited(ReplayGainService.scanLibrary(songs, writeTags: true));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memuat library: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BatchScanProgress>(
      valueListenable: ReplayGainService.scanProgress,
      builder: (context, progress, _) {
        if (progress.running) {
          return _ScanProgressRow(progress: progress);
        }
        if (progress.finished) {
          return _ScanResultRow(
            progress: progress,
            onScanAgain: () => _startScan(context),
          );
        }
        return _ScanIdleRow(onTap: () => _startScan(context));
      },
    );
  }
}

class _ScanIdleRow extends StatelessWidget {
  const _ScanIdleRow({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Scan Library',
                    style: TextStyle(color: Colors.white, fontSize: 15),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Hitung ReplayGain untuk lagu yang belum punya data',
                    style: TextStyle(color: Color(0xFF8E8E93), fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.graphic_eq_rounded, color: Colors.white38, size: 18),
          ],
        ),
      ),
    );
  }
}

class _ScanProgressRow extends StatelessWidget {
  const _ScanProgressRow({required this.progress});
  final BatchScanProgress progress;

  @override
  Widget build(BuildContext context) {
    final pct = progress.total > 0
        ? (progress.done / progress.total).clamp(0.0, 1.0)
        : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  progress.currentTitle.isEmpty
                      ? 'Mempersiapkan...'
                      : progress.currentTitle,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${progress.done} / ${progress.total}',
                style: const TextStyle(
                    color: Color(0xFF8E8E93), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFFF92D48)),
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: ReplayGainService.cancelScan,
            child: const Text(
              'Batalkan',
              style: TextStyle(color: Color(0xFFF92D48), fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanResultRow extends StatelessWidget {
  const _ScanResultRow({
    required this.progress,
    required this.onScanAgain,
  });
  final BatchScanProgress progress;
  final VoidCallback onScanAgain;

  @override
  Widget build(BuildContext context) {
    final String subtitle;
    if (progress.cancelled) {
      subtitle = 'Dibatalkan · ${progress.succeeded} lagu berhasil';
    } else if (progress.failed == 0) {
      subtitle = '${progress.succeeded} lagu berhasil dipindai';
    } else {
      subtitle = '${progress.succeeded} berhasil, ${progress.failed} gagal';
    }

    return InkWell(
      onTap: onScanAgain,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Scan Library',
                    style: TextStyle(color: Colors.white, fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                        color: Color(0xFF8E8E93), fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.replay_rounded,
                color: Colors.white38, size: 18),
          ],
        ),
      ),
    );
  }
}
