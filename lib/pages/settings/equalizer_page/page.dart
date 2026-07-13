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
      backgroundColor: Colors.black,
      appBar: FadingTitleAppBar(
        title: 'Equalizer',
        scrollOffset: 100,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
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
            title: 'Kecepatan Putar',
            subtitle: '${v.toStringAsFixed(2)}x',
            value: v,
            min: 0.25,
            max: 3.0,
            onChanged: AudioEffectsService.setSpeed,
            divisions: 22,
            showReset: v != 1.0,
            onReset: () => AudioEffectsService.setSpeed(1.0),
            description:
                'Mengatur kecepatan pemutaran lagu. Nilai di bawah 1x memperlambat, di atas 1x mempercepat, tanpa mengubah pitch suara.',
          ),
        ),
        const _SectionDivider(),

        // ── Pitch Shift ───────────────────────────────────────────────────────
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
            description:
                'Menaikkan atau menurunkan nada lagu dalam satuan semitone, tanpa mengubah kecepatan putar.',
          ),
        ),
        const _SectionDivider(),

        // ── Bass Boost ────────────────────────────────────────────────────────
        ValueListenableBuilder<int>(
          valueListenable: AudioEffectsService.bassBoost,
          builder: (_, v, _) => SettingsSliderRow(
            title: 'Bass Boost',
            subtitle: v == 0
                ? 'Nonaktif'
                : DeviceDsp.bassBoostSupported
                    ? '${(v / 10).round()}%'
                    : 'Tidak didukung perangkat ini',
            value: v.toDouble(),
            min: 0,
            max: 1000,
            onChanged: (val) => AudioEffectsService.setBassBoost(val.round()),
            divisions: 20,
            showReset: v != 0,
            onReset: () => AudioEffectsService.setBassBoost(0),
            description:
                'Menguatkan frekuensi bass agar suara dentum/rendah terasa lebih tebal. Semakin besar persentase, semakin kuat efeknya.',
          ),
        ),
        const _SectionDivider(),

        // ── Compressor ────────────────────────────────────────────────────────
        //
        // Ratio drives on/off directly: 1:1 = no compression (off). No
        // separate switch — moving the slider above 1:1 engages it.
        ValueListenableBuilder<double>(
          valueListenable: AudioEffectsService.compressorRatio,
          builder: (_, ratio, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SettingsSliderRow(
                title: 'Compressor',
                subtitle: ratio <= 1.0
                    ? 'Nonaktif'
                    : '${ratio.toStringAsFixed(1)}:1',
                value: ratio,
                min: 1.0,
                max: 20.0,
                onChanged: AudioEffectsService.setCompressorRatio,
                divisions: 38,
                showReset: ratio != 1.0,
                onReset: () => AudioEffectsService.setCompressorRatio(1.0),
                description:
                    'Menekan perbedaan volume antara suara pelan dan keras. Rasio lebih tinggi = kompresi lebih agresif. 1:1 berarti nonaktif.',
              ),
              if (ratio > 1.0)
                ValueListenableBuilder<double>(
                  valueListenable: AudioEffectsService.compressorThreshold,
                  builder: (_, v, _) => SettingsSliderRow(
                    title: 'Compressor Threshold',
                    subtitle: '${v.toStringAsFixed(0)} dB',
                    value: v,
                    min: -60.0,
                    max: 0.0,
                    onChanged: AudioEffectsService.setCompressorThreshold,
                    divisions: 60,
                    showReset: v != -20.0,
                    onReset: () =>
                        AudioEffectsService.setCompressorThreshold(-20.0),
                    description:
                        'Ambang batas volume tempat compressor mulai bekerja. Semakin rendah nilainya, semakin banyak bagian suara yang dikompres.',
                  ),
                ),
            ],
          ),
        ),
        const _SectionDivider(),

        // ── Limiter ───────────────────────────────────────────────────────────
        //
        // Ceiling drives on/off directly: 0 dB (top of range) = off. No
        // separate switch — moving the slider below 0 engages it.
        ValueListenableBuilder<double>(
          valueListenable: AudioEffectsService.limiterThreshold,
          builder: (_, v, _) => SettingsSliderRow(
            title: 'Limiter',
            subtitle: v >= 0.0 ? 'Nonaktif' : '${v.toStringAsFixed(1)} dB',
            value: v,
            min: -24.0,
            max: 0.0,
            onChanged: AudioEffectsService.setLimiterThreshold,
            divisions: 48,
            showReset: v != 0.0,
            onReset: () => AudioEffectsService.setLimiterThreshold(0.0),
            description:
                'Mencegah suara melewati batas volume tertentu agar tidak pecah/distorsi. Geser di bawah 0 dB untuk mengaktifkan.',
          ),
        ),
        const _SectionDivider(),

        // ── Soft Clipper ──────────────────────────────────────────────────────
        //
        // Threshold drives on/off directly: 0 dB (top of range) = off. No
        // separate switch — moving the slider below 0 engages it.
        ValueListenableBuilder<double>(
          valueListenable: AudioEffectsService.softClipperThreshold,
          builder: (_, v, _) => SettingsSliderRow(
            title: 'Soft Clipper',
            subtitle: v >= 0.0 ? 'Nonaktif' : '${v.toStringAsFixed(1)} dB',
            value: v,
            min: -12.0,
            max: 0.0,
            onChanged: AudioEffectsService.setSoftClipperThreshold,
            divisions: 24,
            showReset: v != 0.0,
            onReset: () => AudioEffectsService.setSoftClipperThreshold(0.0),
            description:
                'Melunakkan puncak suara yang terlalu keras secara halus, sebagai lapisan pengaman terakhir sebelum output, sehingga distorsi lebih tidak terasa dibanding limiter.',
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
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Divider(color: Color(0xFF2C2C2E), height: 1),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Row(
        children: [
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF8E8E93),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
          if (trailing != null) ...[
            const Spacer(),
            trailing!,
          ],
        ],
      ),
    );
  }
}
