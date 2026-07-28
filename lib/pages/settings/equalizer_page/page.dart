part of '../equalizer_page.dart';

// ─── EqualizerPage ─────────────────────────────────────────────────────────────

class EqualizerPage extends StatefulWidget {
  const EqualizerPage({super.key});

  @override
  State<EqualizerPage> createState() => _EqualizerPageState();
}

class _EqualizerPageState extends State<EqualizerPage> {
  // Jumlah pointer yang sedang aktif menekan/menggeser salah satu band
  // slider vertikal. Selama > 0, scroll halaman dikunci agar drag vertikal
  // di slider tidak ikut menggeser layar (SingleChildScrollView bertumpuk
  // vertikal dengan slider vertikal → gesture bentrok tanpa ini).
  final ValueNotifier<int> _activeBandTouches = ValueNotifier<int>(0);

  @override
  void dispose() {
    _activeBandTouches.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: FadingTitleAppBar(
        title: context.l10n.equalizerTitle,
        scrollOffset: 100,
        leading: CupertinoButton(
          padding: const EdgeInsets.only(left: 8),
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Icon(
            CupertinoIcons.arrow_left,
            color: Color(0xFFF92D48),
            size: 28,
          ),
        ),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: AudioEffectsService.bitPerfectMode,
            builder: (_, bitPerfect, _) => ValueListenableBuilder<bool>(
              valueListenable: AudioEffectsService.equalizerEnabled,
              builder: (_, enabled, _) => CupertinoSwitch(
                value: enabled,
                onChanged: bitPerfect
                    ? null
                    : AudioEffectsService.setEqualizerEnabled,
                activeTrackColor: const Color(0xFFF92D48),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ValueListenableBuilder<int>(
          valueListenable: _activeBandTouches,
          builder: (_, touches, child) => SingleChildScrollView(
            physics: touches > 0
                ? const NeverScrollableScrollPhysics()
                : const ClampingScrollPhysics(),
            child: child,
          ),
          child: BitPerfectLock(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                const _EqPresetChips(),
                _EqBandSliderSection(activeTouches: _activeBandTouches),
                const _SectionDivider(),
                const _AdvancedAudioControls(),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Advanced audio controls ────────────────────────────────────────────────
//
// Kecepatan Putar, Pitch Shift, Bass Boost, Compressor, Limiter, dan Soft
// Clipper — dipindahkan ke sini dari section Audio. Semua slider tampil
// langsung tanpa expand/collapse (expandable: false, default).

class _AdvancedAudioControls extends StatelessWidget {
  const _AdvancedAudioControls();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Kecepatan Putar ───────────────────────────────────────────────────
        ValueListenableBuilder<double>(
          valueListenable: AudioEffectsService.playbackSpeed,
          builder: (_, v, _) => SettingsSliderRow(
            title: context.l10n.playbackSpeed,
            subtitle: '${v.toStringAsFixed(2)}x',
            value: v,
            min: 0.25,
            max: 3.0,
            onChanged: AudioEffectsService.setSpeed,
            divisions: 22,
            showReset: v != 1.0,
            onReset: () => AudioEffectsService.setSpeed(1.0),
            description: context.l10n.speedDesc,
          ),
        ),
        const _SectionDivider(),

        // ── Pitch Shift ───────────────────────────────────────────────────────
        ValueListenableBuilder<double>(
          valueListenable: AudioEffectsService.pitchShift,
          builder: (_, v, _) => SettingsSliderRow(
            title: context.l10n.pitchShift,
            subtitle: v == 0
                ? context.l10n.normal
                : context.l10n.pitchSemitone(
                    '${v > 0 ? '+' : ''}${v.toStringAsFixed(1)}',
                  ),
            value: v,
            min: -6,
            max: 6,
            onChanged: AudioEffectsService.setPitch,
            divisions: 24,
            showReset: v != 0,
            onReset: () => AudioEffectsService.setPitch(0),
            description: context.l10n.pitchDesc,
          ),
        ),
        const _SectionDivider(),

        // ── Bass Boost ────────────────────────────────────────────────────────
        ValueListenableBuilder<int>(
          valueListenable: AudioEffectsService.bassBoost,
          builder: (_, v, _) => SettingsSliderRow(
            title: context.l10n.bassBoost,
            subtitle: v == 0
                ? context.l10n.off
                : DeviceDsp.bassBoostSupported
                ? '${(v / 10).round()}%'
                : context.l10n.notSupportedDevice,
            value: v.toDouble(),
            min: 0,
            max: 1000,
            onChanged: (val) => AudioEffectsService.setBassBoost(val.round()),
            divisions: 20,
            showReset: v != 0,
            onReset: () => AudioEffectsService.setBassBoost(0),
            description: context.l10n.bassBoostDesc,
          ),
        ),
        const _SectionDivider(),

        // ── Native Preamp ─────────────────────────────────────────────────────
        ValueListenableBuilder<double>(
          valueListenable: AudioEffectsService.nativePreampDb,
          builder: (_, v, _) => SettingsSliderRow(
            title: context.l10n.preamp,
            subtitle: v == 0.0
                ? context.l10n.off
                : context.l10n.decibelValue(
                    '${v > 0 ? '+' : ''}${v.toStringAsFixed(1)}',
                  ),
            value: v,
            min: -24.0,
            max: 24.0,
            onChanged: AudioEffectsService.setNativePreampDb,
            divisions: 96,
            showReset: v != 0.0,
            onReset: () => AudioEffectsService.setNativePreampDb(0.0),
            description: context.l10n.preampDesc,
          ),
        ),
        const _SectionDivider(),

        // ── Compressor ────────────────────────────────────────────────────────
        ValueListenableBuilder<double>(
          valueListenable: AudioEffectsService.compressorRatio,
          builder: (_, ratio, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SettingsSliderRow(
                title: context.l10n.compressor,
                subtitle: ratio <= 1.0
                    ? context.l10n.off
                    : '${ratio.toStringAsFixed(1)}:1',
                value: ratio,
                min: 1.0,
                max: 20.0,
                onChanged: AudioEffectsService.setCompressorRatio,
                divisions: 38,
                showReset: ratio != 1.0,
                onReset: () => AudioEffectsService.setCompressorRatio(1.0),
                description: context.l10n.compressorDesc,
              ),
              if (ratio > 1.0) ...[
                ValueListenableBuilder<double>(
                  valueListenable: AudioEffectsService.compressorThreshold,
                  builder: (_, v, _) => SettingsSliderRow(
                    title: context.l10n.compressorThresholdTitle,
                    subtitle: context.l10n.decibelValue(v.toStringAsFixed(0)),
                    value: v,
                    min: -60.0,
                    max: 0.0,
                    onChanged: AudioEffectsService.setCompressorThreshold,
                    divisions: 60,
                    showReset: v != -20.0,
                    onReset: () =>
                        AudioEffectsService.setCompressorThreshold(-20.0),
                    description: context.l10n.compressorThresholdDesc,
                  ),
                ),
                ValueListenableBuilder<double>(
                  valueListenable: AudioEffectsService.compressorAttackMs,
                  builder: (_, v, _) => SettingsSliderRow(
                    title: context.l10n.compressorAttackTitle,
                    subtitle: context.l10n.millisecondsValue(
                      v.toStringAsFixed(0),
                    ),
                    value: v,
                    min: 0.1,
                    max: 500.0,
                    onChanged: AudioEffectsService.setCompressorAttackMs,
                    divisions: 50,
                    showReset: v != 10.0,
                    onReset: () =>
                        AudioEffectsService.setCompressorAttackMs(10.0),
                    description: context.l10n.compressorAttackDesc,
                  ),
                ),
                ValueListenableBuilder<double>(
                  valueListenable: AudioEffectsService.compressorReleaseMs,
                  builder: (_, v, _) => SettingsSliderRow(
                    title: context.l10n.compressorReleaseTitle,
                    subtitle: context.l10n.millisecondsValue(
                      v.toStringAsFixed(0),
                    ),
                    value: v,
                    min: 1.0,
                    max: 2000.0,
                    onChanged: AudioEffectsService.setCompressorReleaseMs,
                    divisions: 40,
                    showReset: v != 100.0,
                    onReset: () =>
                        AudioEffectsService.setCompressorReleaseMs(100.0),
                    description: context.l10n.compressorReleaseDesc,
                  ),
                ),
                ValueListenableBuilder<double>(
                  valueListenable: AudioEffectsService.compressorKneeDb,
                  builder: (_, v, _) => SettingsSliderRow(
                    title: context.l10n.compressorKneeTitle,
                    subtitle: v == 0.0
                        ? context.l10n.hardKnee
                        : context.l10n.decibelValue(v.toStringAsFixed(0)),
                    value: v,
                    min: 0.0,
                    max: 24.0,
                    onChanged: AudioEffectsService.setCompressorKneeDb,
                    divisions: 24,
                    showReset: v != 6.0,
                    onReset: () => AudioEffectsService.setCompressorKneeDb(6.0),
                    description: context.l10n.compressorKneeDesc,
                  ),
                ),
              ],
            ],
          ),
        ),
        const _SectionDivider(),

        // ── Limiter ───────────────────────────────────────────────────────────
        ValueListenableBuilder<double>(
          valueListenable: AudioEffectsService.limiterThreshold,
          builder: (_, v, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SettingsSliderRow(
                title: context.l10n.limiter,
                subtitle: v >= 0.0
                    ? context.l10n.off
                    : context.l10n.decibelValue(v.toStringAsFixed(1)),
                value: v,
                min: -24.0,
                max: 0.0,
                onChanged: AudioEffectsService.setLimiterThreshold,
                divisions: 48,
                showReset: v != 0.0,
                onReset: () => AudioEffectsService.setLimiterThreshold(0.0),
                description: context.l10n.limiterDesc,
              ),
              if (v < 0.0)
                ValueListenableBuilder<double>(
                  valueListenable: AudioEffectsService.limiterReleaseMs,
                  builder: (_, r, _) => SettingsSliderRow(
                    title: context.l10n.limiterReleaseTitle,
                    subtitle: context.l10n.millisecondsValue(
                      r.toStringAsFixed(0),
                    ),
                    value: r,
                    min: 1.0,
                    max: 1000.0,
                    onChanged: AudioEffectsService.setLimiterReleaseMs,
                    divisions: 50,
                    showReset: r != 50.0,
                    onReset: () =>
                        AudioEffectsService.setLimiterReleaseMs(50.0),
                    description: context.l10n.limiterReleaseDesc,
                  ),
                ),
            ],
          ),
        ),
        const _SectionDivider(),

        // ── Soft Clipper ──────────────────────────────────────────────────────
        ValueListenableBuilder<double>(
          valueListenable: AudioEffectsService.softClipperThreshold,
          builder: (_, v, _) => SettingsSliderRow(
            title: context.l10n.softClipper,
            subtitle: v >= 0.0
                ? context.l10n.off
                : context.l10n.decibelValue(v.toStringAsFixed(1)),
            value: v,
            min: -12.0,
            max: 0.0,
            onChanged: AudioEffectsService.setSoftClipperThreshold,
            divisions: 24,
            showReset: v != 0.0,
            onReset: () => AudioEffectsService.setSoftClipperThreshold(0.0),
            description: context.l10n.softClipperDesc,
          ),
        ),
      ],
    );
  }
}

// ─── Reusable section divider ─────────────────────────────────────────────────

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Divider(color: AppColors.of(context).surface2, height: 1),
    );
  }
}

// ─── Section label ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Row(
        children: [
          Text(
            text,
            style: TextStyle(
              color: c.secondaryLabel,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
          if (trailing != null) ...[const Spacer(), trailing!],
        ],
      ),
    );
  }
}
