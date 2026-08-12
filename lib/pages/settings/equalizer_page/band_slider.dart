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
  const _EqBandSliderSection({required this.activeTouches});

  /// Shared counter of active pointers currently dragging a band slider.
  /// Passed up to [EqualizerPage] so it can lock page scrolling while any
  /// band slider is being touched.
  final ValueNotifier<int> activeTouches;

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
    unawaited(_loadNativeParams());
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
      final rawLabels = params.bands
          .map((b) => _formatHz(b.centerFrequencyHz))
          .toList();
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
    } on Exception catch (_) {
      // Native unavailable — use defaults, restore from prefs
      await _restoreGainsFromPrefs(_freqLabels.length);
    }
  }

  Future<void> _restoreGainsFromPrefs(int count) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = List.generate(
      count,
      (i) => prefs.getDouble('eqBand_$i') ?? 0.0,
    );
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
    unawaited(AudioEffectsService.setEqualizerBandGain(index, value));
  }

  void _resetAll() {
    final count = _gains.length;
    setState(() => _gains = List.filled(count, 0.0));
    for (var i = 0; i < count; i++) {
      unawaited(AudioEffectsService.setEqualizerBandGain(i, 0.0));
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
              context.l10n.bandEq,
              trailing: enabled
                  ? GestureDetector(
                      onTap: _resetAll,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        child: Text(
                          context.l10n.reset,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
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
                          activeTouches: widget.activeTouches,
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
// _VerticalBandSlider + _VerticalBandSliderState dipindah ke part file:
//   equalizer_page/band_slider_vertical.dart

// ─── Custom painter ────────────────────────────────────────────────────────────
// _BandTrackPainter dipindah ke part file:
//   equalizer_page/band_track_painter.dart

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
