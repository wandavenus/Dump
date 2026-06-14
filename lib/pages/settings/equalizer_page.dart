import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:just_audio/just_audio.dart';

import '../../services/audio/audio_effects_service.dart';

class EqualizerPage extends StatefulWidget {
  const EqualizerPage({super.key});

  @override
  State<EqualizerPage> createState() => _EqualizerPageState();
}

class _EqualizerPageState extends State<EqualizerPage> {
  AndroidEqualizerParameters? _params;
  bool _loading = true;
  String? _error;
  int _selectedPreset = 0;

  @override
  void initState() {
    super.initState();
    _loadParameters();
  }

  Future<void> _loadParameters() async {
    try {
      final params = await AudioEffectsService.getEqualizerParameters();
      if (mounted) {
        setState(() {
          _params = params;
          _loading = false;
        });
        if (params != null) {
          await AudioEffectsService.restoreEqualizerBands();
          if (mounted) setState(() {});
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Equalizer tidak tersedia di perangkat ini.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(context),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.of(context).pop(),
            child: const Icon(CupertinoIcons.back, color: Colors.white),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Equalizer',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: AudioEffectsService.equalizerEnabled,
            builder: (_, enabled, __) => CupertinoSwitch(
              value: enabled,
              onChanged: AudioEffectsService.setEqualizerEnabled,
              activeColor: const Color(0xFFF92D48),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null || _params == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _error ?? 'Equalizer tidak tersedia.',
            style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 15),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ValueListenableBuilder<bool>(
      valueListenable: AudioEffectsService.equalizerEnabled,
      builder: (_, enabled, __) => Column(
        children: [
          // ── Presets ──────────────────────────────────────────────────────
          _PresetsRow(
            selectedPreset: _selectedPreset,
            enabled: enabled,
            onPresetSelected: (i) async {
              await AudioEffectsService.applyEqPreset(i);
              if (mounted) {
                setState(() => _selectedPreset = i);
                // Reload params so UI reflects new gains
                final fresh =
                    await AudioEffectsService.getEqualizerParameters();
                if (mounted) setState(() => _params = fresh);
              }
            },
          ),
          const SizedBox(height: 8),
          // ── Band sliders ─────────────────────────────────────────────────
          Expanded(
            child: _BandsView(
              params: _params!,
              enabled: enabled,
              onBandChanged: (i, gain) =>
                  AudioEffectsService.setEqualizerBandGain(i, gain),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Presets row ──────────────────────────────────────────────────────────────

class _PresetsRow extends StatelessWidget {
  final int selectedPreset;
  final bool enabled;
  final void Function(int) onPresetSelected;

  const _PresetsRow({
    required this.selectedPreset,
    required this.enabled,
    required this.onPresetSelected,
  });

  @override
  Widget build(BuildContext context) {
    final presets = AudioEffectsService.eqPresets;

    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: presets.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final selected = i == selectedPreset;
          return GestureDetector(
            onTap: enabled ? () => onPresetSelected(i) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFFF92D48)
                    : const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                presets[i]['name'] as String,
                style: TextStyle(
                  color: selected
                      ? Colors.white
                      : const Color(0xFF8E8E93),
                  fontSize: 13,
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Band sliders ─────────────────────────────────────────────────────────────

class _BandsView extends StatefulWidget {
  final AndroidEqualizerParameters params;
  final bool enabled;
  final void Function(int bandIndex, double gain) onBandChanged;

  const _BandsView({
    required this.params,
    required this.enabled,
    required this.onBandChanged,
  });

  @override
  State<_BandsView> createState() => _BandsViewState();
}

class _BandsViewState extends State<_BandsView> {
  late List<double> _gains;

  @override
  void initState() {
    super.initState();
    _gains = widget.params.bands.map((b) => b.gain).toList();
  }

  @override
  void didUpdateWidget(_BandsView old) {
    super.didUpdateWidget(old);
    _gains = widget.params.bands.map((b) => b.gain).toList();
  }

  String _freqLabel(double hz) {
    if (hz >= 1000) {
      final k = hz / 1000;
      return '${k % 1 == 0 ? k.toStringAsFixed(0) : k.toStringAsFixed(1)}k';
    }
    return hz.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final bands = widget.params.bands;
    final minDb = widget.params.minDecibels;
    final maxDb = widget.params.maxDecibels;

    // dB steps for y-axis labels
    final range = (maxDb - minDb).round();
    final step = range ~/ 4;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // dB labels column
          Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var db = maxDb.round(); db >= minDb.round(); db -= step)
                Text(
                  '${db > 0 ? '+' : ''}$db',
                  style: const TextStyle(
                      color: Color(0xFF8E8E93), fontSize: 10),
                ),
            ],
          ),
          const SizedBox(width: 12),
          // Band sliders
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(bands.length, (i) {
                return Expanded(
                  child: _BandSlider(
                    freqLabel: _freqLabel(bands[i].centerFrequency),
                    gain: _gains.length > i ? _gains[i] : 0.0,
                    minDb: minDb,
                    maxDb: maxDb,
                    enabled: widget.enabled,
                    onChanged: (v) {
                      setState(() => _gains[i] = v);
                      widget.onBandChanged(i, v);
                    },
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _BandSlider extends StatelessWidget {
  final String freqLabel;
  final double gain;
  final double minDb;
  final double maxDb;
  final bool enabled;
  final ValueChanged<double> onChanged;

  const _BandSlider({
    required this.freqLabel,
    required this.gain,
    required this.minDb,
    required this.maxDb,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Gain value indicator
        Text(
          '${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)}',
          style: const TextStyle(
            color: Color(0xFFF92D48),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        // Vertical slider
        Expanded(
          child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: enabled
                    ? const Color(0xFFF92D48)
                    : const Color(0xFF48484A),
                thumbColor:
                    enabled ? Colors.white : const Color(0xFF636366),
                inactiveTrackColor: const Color(0xFF48484A),
                overlayColor: const Color(0x29F92D48),
                trackHeight: 3,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 7),
              ),
              child: Slider(
                value: gain.clamp(minDb, maxDb),
                min: minDb,
                max: maxDb,
                onChanged: enabled ? onChanged : null,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          freqLabel,
          style: const TextStyle(
            color: Color(0xFF8E8E93),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
