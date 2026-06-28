part of '../equalizer_page.dart';

// ─── EQ Band Slider Section ────────────────────────────────────────────────────
//
// Menampilkan vertical slider untuk setiap EQ band.
//
// Implementasi native:
//   • Jumlah band    — android.media.audiofx.Equalizer.numberOfBands (dinamis)
//   • Range dB       — Equalizer.bandLevelRange (dalam millibels, dikonversi ke dB)
//   • Frekuensi      — Equalizer.getCenterFreq(band) dalam millihertz → Hz
//   • Gain           — Equalizer.setBandLevel(band, gainMillibels)
//
// Semua nilai dibaca dari native via Media3PlaybackBridge.getEqualizerParameters().
// Fallback ke default 5-band jika native belum tersedia (web, emulator, service belum
// terhubung). Jangan hardcode jumlah band.
//
// Multitouch: setiap _VerticalBandSlider menggunakan Listener (bukan GestureDetector)
// sehingga setiap pointer di-track secara independen. Dua jari pada dua slider yang
// berbeda berjalan bersamaan tanpa konflik gesture arena.

// ─── State ────────────────────────────────────────────────────────────────────

class _EqBandSliderSection extends StatefulWidget {
  const _EqBandSliderSection();

  @override
  State<_EqBandSliderSection> createState() => _EqBandSliderSectionState();
}

class _EqBandSliderSectionState extends State<_EqBandSliderSection> {
  static const _defaultLabels = ['60Hz', '230Hz', '910Hz', '3.6k', '14k'];

  List<double> _gains = List.filled(5, 0.0);
  List<String> _freqLabels = List.of(_defaultLabels);
  double _minDb = -15.0;
  double _maxDb = 15.0;

  @override
  void initState() {
    super.initState();
    AudioEffectsService.eqPreset.addListener(_onPresetChanged);
    _loadNativeParams();
  }

  @override
  void dispose() {
    AudioEffectsService.eqPreset.removeListener(_onPresetChanged);
    super.dispose();
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _loadNativeParams() async {
    if (kIsWeb) {
      await _restoreGainsFromPrefs(_freqLabels.length);
      return;
    }
    try {
      final params = await Media3PlaybackBridge.getEqualizerParameters();
      final rawLabels = params.bands.map((b) => _formatHz(b.centerFrequencyHz)).toList();
      final labels = rawLabels.every((l) => l != '?') && rawLabels.isNotEmpty
          ? rawLabels
          : _defaultLabels;
      final count = labels.length;

      if (!mounted) return;
      setState(() {
        _minDb = params.minDecibels;
        _maxDb = params.maxDecibels;
        _freqLabels = labels;
        _gains = List.filled(count, 0.0);
      });
      await _restoreGainsFromPrefs(count);
    } catch (_) {
      // Native unavailable — use defaults, restore from prefs
      await _restoreGainsFromPrefs(_freqLabels.length);
    }
  }

  Future<void> _restoreGainsFromPrefs(int count) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = List.generate(count, (i) => prefs.getDouble('eqBand_$i') ?? 0.0);
    if (mounted) setState(() => _gains = saved);
  }

  /// Called when a preset chip is tapped — update sliders to match preset gains.
  void _onPresetChanged() {
    final idx = AudioEffectsService.eqPreset.value;
    if (idx < 0 || idx >= AudioEffectsService.eqPresets.length) return;
    final gains = AudioEffectsService.eqPresets[idx]['gains'] as List<double>;
    if (!mounted) return;
    setState(() {
      _gains = List.generate(_freqLabels.length, (i) {
        return i < gains.length ? gains[i].clamp(_minDb, _maxDb) : 0.0;
      });
    });
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  void _onBandChanged(int index, double value) {
    setState(() {
      if (index < _gains.length) _gains[index] = value;
    });
    AudioEffectsService.setEqualizerBandGain(index, value);
  }

  void _resetAll() {
    final count = _gains.length;
    setState(() => _gains = List.filled(count, 0.0));
    for (var i = 0; i < count; i++) {
      AudioEffectsService.setEqualizerBandGain(i, 0.0);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AudioEffectsService.equalizerEnabled,
      builder: (_, enabled, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionLabel(
              'BAND EQ',
              trailing: enabled
                  ? GestureDetector(
                      onTap: _resetAll,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Text(
                          'Reset',
                          style: TextStyle(
                            color: Color(0xFFF92D48),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 16),
            AnimatedOpacity(
              opacity: enabled ? 1.0 : 0.38,
              duration: const Duration(milliseconds: 220),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(
                  height: 200,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: List.generate(_freqLabels.length, (i) {
                      return Expanded(
                        child: _VerticalBandSlider(
                          gain: i < _gains.length ? _gains[i] : 0.0,
                          freqLabel: _freqLabels[i],
                          min: _minDb,
                          max: _maxDb,
                          enabled: enabled,
                          onChanged: (v) => _onBandChanged(i, v),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }
}

// ─── Single vertical band slider ───────────────────────────────────────────────

class _VerticalBandSlider extends StatefulWidget {
  const _VerticalBandSlider({
    required this.gain,
    required this.freqLabel,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onChanged,
  });

  final double gain;
  final String freqLabel;
  final double min;
  final double max;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  State<_VerticalBandSlider> createState() => _VerticalBandSliderState();
}

class _VerticalBandSliderState extends State<_VerticalBandSlider>
    with SingleTickerProviderStateMixin {
  /// Pointer ID currently dragging this slider. Null = idle.
  int? _activePointer;

  /// Animation controller for the "pressing" highlight effect.
  late final AnimationController _pressCtrl;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  // ── Pointer tracking (multitouch-safe via Listener) ───────────────────────

  void _onPointerDown(PointerDownEvent e, BoxConstraints c) {
    if (!widget.enabled || _activePointer != null) return;
    _activePointer = e.pointer;
    _pressCtrl.forward();
    final v = _yToValue(e.localPosition.dy, c.maxHeight);
    widget.onChanged(v);
  }

  void _onPointerMove(PointerMoveEvent e, BoxConstraints c) {
    if (e.pointer != _activePointer || !widget.enabled) return;
    final v = _yToValue(e.localPosition.dy, c.maxHeight);
    widget.onChanged(v);
  }

  void _onPointerUp(PointerUpEvent e) {
    if (e.pointer != _activePointer) return;
    _activePointer = null;
    _pressCtrl.reverse();
  }

  void _onPointerCancel(PointerCancelEvent e) {
    if (e.pointer != _activePointer) return;
    _activePointer = null;
    _pressCtrl.reverse();
  }

  /// Convert a raw Y coordinate within the track area to a gain value.
  double _yToValue(double y, double trackH) {
    final fraction = 1.0 - (y / trackH).clamp(0.0, 1.0);
    final raw = widget.min + fraction * (widget.max - widget.min);
    // Snap to 0 when within 0.3 dB to make it easy to land on center.
    if (raw.abs() < 0.3) return 0.0;
    return raw.clamp(widget.min, widget.max);
  }

  // ── Label helpers ─────────────────────────────────────────────────────────

  String get _gainLabel {
    final g = widget.gain;
    if (g.abs() < 0.05) return '0';
    return '${g > 0 ? '+' : ''}${g.toStringAsFixed(1)}';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isActive = widget.gain.abs() > 0.1;
    final isDragging = _activePointer != null;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // ── dB value label ───────────────────────────────────────────
        SizedBox(
          height: 20,
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 150),
            style: TextStyle(
              color: isDragging || isActive
                  ? const Color(0xFFF92D48)
                  : const Color(0xFF636366),
              fontSize: 10,
              fontWeight:
                  isDragging || isActive ? FontWeight.w600 : FontWeight.normal,
            ),
            child: Text(_gainLabel, textAlign: TextAlign.center),
          ),
        ),

        const SizedBox(height: 4),

        // ── Slider track (Listener for multitouch-safe drags) ────────
        Expanded(
          child: LayoutBuilder(
            builder: (_, constraints) => Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (e) => _onPointerDown(e, constraints),
              onPointerMove: (e) => _onPointerMove(e, constraints),
              onPointerUp: _onPointerUp,
              onPointerCancel: _onPointerCancel,
              child: AnimatedBuilder(
                animation: _pressCtrl,
                builder: (_, _) => CustomPaint(
                  size: Size(constraints.maxWidth, constraints.maxHeight),
                  painter: _BandTrackPainter(
                    gain: widget.gain,
                    min: widget.min,
                    max: widget.max,
                    pressAmount: _pressCtrl.value,
                    enabled: widget.enabled,
                  ),
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 6),

        // ── Frequency label ──────────────────────────────────────────
        SizedBox(
          height: 16,
          child: Text(
            widget.freqLabel,
            style: const TextStyle(
              color: Color(0xFF8E8E93),
              fontSize: 10,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

// ─── Custom painter ────────────────────────────────────────────────────────────
//
// Menggambar track vertikal dengan:
//   • Track utama (abu-abu tipis, full height)
//   • Porsi aktif (merah) dari titik 0dB ke posisi thumb
//   • Garis center di 0dB (tick mark horizontal kecil)
//   • Thumb (lingkaran) dengan glow saat ditekan
//   • Warna intensitas bertahap dari abu ke merah sesuai besar gain

class _BandTrackPainter extends CustomPainter {
  const _BandTrackPainter({
    required this.gain,
    required this.min,
    required this.max,
    required this.pressAmount,
    required this.enabled,
  });

  final double gain;
  final double min;
  final double max;
  final double pressAmount;
  final bool enabled;

  static const _trackW = 3.0;
  static const _thumbBaseR = 7.0;
  static const _thumbPressExtra = 2.5;
  static const _centerTickHalfW = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    final range = max - min;
    if (range <= 0) return;

    final cx = size.width / 2;
    final gainFraction = (gain - min) / range;          // 0.0 (min) → 1.0 (max)
    final zeroFraction = (-min) / range;                // position of 0 dB
    final thumbY = size.height * (1.0 - gainFraction);
    final centerY = size.height * (1.0 - zeroFraction);

    // ── Colours ──────────────────────────────────────────────────────────────
    const trackBg = Color(0xFF3A3A3C);
    const centerTick = Color(0xFF636366);
    final accentColor = enabled
        ? Color.lerp(
            const Color(0xFF888888),
            const Color(0xFFF92D48),
            (gain.abs() / (range / 2)).clamp(0.0, 1.0),
          )!
        : const Color(0xFF3A3A3C);
    final thumbColor = enabled
        ? Color.lerp(const Color(0xFF8A8A8E), const Color(0xFFF92D48),
            (gain.abs() / (range / 2)).clamp(0.0, 1.0) * 0.8 + pressAmount * 0.2)!
        : const Color(0xFF5A5A5E);

    // ── Background track ─────────────────────────────────────────────────────
    final bgPaint = Paint()
      ..color = trackBg
      ..strokeWidth = _trackW
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), bgPaint);

    // ── Active fill (center → thumb) ─────────────────────────────────────────
    if (gain.abs() > 0.05) {
      final activePaint = Paint()
        ..color = accentColor
        ..strokeWidth = _trackW + pressAmount
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(cx, gain > 0 ? thumbY : centerY),
        Offset(cx, gain > 0 ? centerY : thumbY),
        activePaint,
      );
    }

    // ── Center tick (0 dB reference) ─────────────────────────────────────────
    final centerPaint = Paint()
      ..color = centerTick
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(cx - _centerTickHalfW, centerY),
      Offset(cx + _centerTickHalfW, centerY),
      centerPaint,
    );

    // ── Thumb glow (when pressed or gain ≠ 0) ────────────────────────────────
    final glowOpacity = (pressAmount * 0.25 +
        (gain.abs() > 0.1 ? 0.08 : 0.0));
    if (glowOpacity > 0 && enabled) {
      final glowPaint = Paint()
        ..color = const Color(0xFFF92D48).withValues(alpha: glowOpacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(
        Offset(cx, thumbY),
        _thumbBaseR + _thumbPressExtra + 4,
        glowPaint,
      );
    }

    // ── Thumb ────────────────────────────────────────────────────────────────
    final thumbR = _thumbBaseR + pressAmount * _thumbPressExtra;
    final thumbPaint = Paint()..color = thumbColor;
    canvas.drawCircle(Offset(cx, thumbY), thumbR, thumbPaint);

    // Inner highlight on thumb
    if (enabled && gain.abs() > 0.05) {
      final innerPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.18 + pressAmount * 0.12);
      canvas.drawCircle(Offset(cx, thumbY), thumbR * 0.45, innerPaint);
    }
  }

  @override
  bool shouldRepaint(_BandTrackPainter old) =>
      old.gain != gain ||
      old.pressAmount != pressAmount ||
      old.enabled != enabled ||
      old.min != min ||
      old.max != max;
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

/// Format Hz value to a readable label (e.g., 14000 → "14k", 230 → "230Hz").
String _formatHz(int hz) {
  if (hz <= 0) return '?';
  if (hz >= 1000) {
    final k = hz / 1000;
    if (k == k.roundToDouble()) return '${k.round()}k';
    return '${k.toStringAsFixed(1)}k';
  }
  return '${hz}Hz';
}
