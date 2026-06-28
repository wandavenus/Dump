part of '../equalizer_page.dart';

// ─── Band EQ slider section ────────────────────────────────────────────────────
//
// Menampilkan vertical slider untuk setiap band EQ.
// Frekuensi label diambil dari native (Media3PlaybackBridge.getEqualizerParameters)
// sehingga mencerminkan hardware yang sebenarnya di perangkat pengguna.
// Fallback ke label default 5-band jika native tidak tersedia (web, emulator).

class _BandSliderSection extends StatefulWidget {
  const _BandSliderSection();

  @override
  State<_BandSliderSection> createState() => _BandSliderSectionState();
}

class _BandSliderSectionState extends State<_BandSliderSection> {
  static const _defaultLabels = ['60Hz', '230Hz', '910Hz', '3.6k', '14k'];

  List<double> _gains = List.filled(5, 0.0);
  List<String> _freqLabels = _defaultLabels;
  double _minDb = -15.0;
  double _maxDb = 15.0;

  // Tracks the last applied room preset so we can refresh slider positions
  // when a preset is tapped without waiting for a full rebuild cycle.
  int _lastPreset = -1;

  @override
  void initState() {
    super.initState();
    _loadNativeParams();
    _loadSavedGains();
    AudioEffectsService.roomPreset.addListener(_onPresetChanged);
  }

  @override
  void dispose() {
    AudioEffectsService.roomPreset.removeListener(_onPresetChanged);
    super.dispose();
  }

  // ── data loading ─────────────────────────────────────────────────────────

  Future<void> _loadNativeParams() async {
    if (kIsWeb) return;
    try {
      final params = await Media3PlaybackBridge.getEqualizerParameters();
      final labels = params.bands.map((b) {
        final hz = b.centerFrequencyHz;
        if (hz <= 0) return '?';
        if (hz >= 1000) {
          final k = hz / 1000;
          return k == k.roundToDouble()
              ? '${k.round()}k'
              : '${k.toStringAsFixed(1)}k';
        }
        return '${hz}Hz';
      }).toList();

      if (!mounted) return;
      setState(() {
        _minDb = params.minDecibels;
        _maxDb = params.maxDecibels;
        if (labels.isNotEmpty &&
            labels.every((l) => l != '?')) {
          _freqLabels = labels;
        }
        // Pad gains list if native has more/fewer bands than default
        if (_gains.length != labels.length) {
          _gains = List.generate(labels.length, (i) {
            return i < _gains.length ? _gains[i] : 0.0;
          });
        }
      });
    } catch (_) {
      // Stay with defaults on error
    }
  }

  Future<void> _loadSavedGains() async {
    final prefs = await SharedPreferences.getInstance();
    final bandCount = _freqLabels.length;
    final saved = List.generate(
      bandCount,
      (i) => prefs.getDouble('eqBand_$i') ?? 0.0,
    );
    if (mounted) setState(() => _gains = saved);
  }

  void _onPresetChanged() {
    final preset = AudioEffectsService.roomPreset.value;
    if (preset == _lastPreset) return;
    _lastPreset = preset;
    final gains =
        AudioEffectsService.roomPresets[preset]['gains'] as List<double>;
    if (mounted) {
      setState(() {
        _gains = List.generate(_freqLabels.length, (i) {
          return i < gains.length ? gains[i] : 0.0;
        });
      });
    }
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  void _onBandChanged(int index, double value) {
    setState(() => _gains[index] = value);
    AudioEffectsService.setEqualizerBandGain(index, value);
  }

  void _resetAll() {
    setState(() => _gains = List.filled(_freqLabels.length, 0.0));
    for (var i = 0; i < _freqLabels.length; i++) {
      AudioEffectsService.setEqualizerBandGain(i, 0.0);
    }
    // Also reset to Flat room preset
    AudioEffectsService.setRoomPreset(0);
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AudioEffectsService.equalizerEnabled,
      builder: (_, enabled, _) {
        return AnimatedOpacity(
          opacity: enabled ? 1.0 : 0.38,
          duration: const Duration(milliseconds: 220),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Section header ───────────────────────────────────────
                Row(
                  children: [
                    const Text(
                      'BAND EQ',
                      style: TextStyle(
                        color: Color(0xFF8E8E93),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Spacer(),
                    if (enabled)
                      GestureDetector(
                        onTap: _resetAll,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          child: Text(
                            'Reset',
                            style: TextStyle(
                              color: Color(0xFFF92D48),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),

                // ── Band sliders ─────────────────────────────────────────
                SizedBox(
                  height: 130,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: List.generate(_freqLabels.length, (i) {
                      return Expanded(
                        child: _SingleBandSlider(
                          gain: i < _gains.length ? _gains[i] : 0.0,
                          label: _freqLabels[i],
                          min: _minDb,
                          max: _maxDb,
                          enabled: enabled,
                          onChanged: (v) => _onBandChanged(i, v),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Single band vertical slider ──────────────────────────────────────────────

class _SingleBandSlider extends StatelessWidget {
  const _SingleBandSlider({
    required this.gain,
    required this.label,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onChanged,
  });

  final double gain;
  final String label;
  final double min;
  final double max;
  final bool enabled;
  final ValueChanged<double> onChanged;

  String get _gainLabel {
    if (gain.abs() < 0.05) return '0';
    return '${gain > 0 ? '+' : ''}${gain.toStringAsFixed(1)}';
  }

  @override
  Widget build(BuildContext context) {
    final isActive = gain.abs() > 0.1;
    final activeColor = const Color(0xFFF92D48);
    final inactiveColor = const Color(0xFF636366);
    final labelColor =
        isActive ? activeColor : const Color(0xFF8E8E93);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // ── Gain value ─────────────────────────────────────────────
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 150),
          style: TextStyle(
            color: labelColor,
            fontSize: 10,
            fontWeight:
                isActive ? FontWeight.w600 : FontWeight.normal,
          ),
          child: Text(_gainLabel),
        ),
        const SizedBox(height: 2),

        // ── Vertical slider (rotated horizontal Slider) ────────────
        Expanded(
          child: RotatedBox(
            quarterTurns: -1,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                activeTrackColor:
                    isActive ? activeColor : const Color(0xFF4A4A4E),
                inactiveTrackColor: const Color(0xFF3A3A3C),
                thumbColor: activeColor,
                thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6),
                overlayShape: SliderComponentShape.noOverlay,
                disabledThumbColor: const Color(0xFF636366),
                disabledActiveTrackColor: const Color(0xFF3A3A3C),
                disabledInactiveTrackColor: const Color(0xFF2C2C2E),
              ),
              child: Slider(
                value: gain.clamp(min, max),
                min: min,
                max: max,
                divisions: ((max - min) * 2).round(),
                onChanged: enabled ? onChanged : null,
              ),
            ),
          ),
        ),

        const SizedBox(height: 2),

        // ── Frequency label ────────────────────────────────────────
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF8E8E93),
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}
