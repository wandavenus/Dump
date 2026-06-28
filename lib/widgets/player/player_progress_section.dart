import 'package:flutter/material.dart';

import '../../services/audio_service.dart';
import '../../services/audio/audio_effects_service.dart';

// ─── PlayerProgressSection ────────────────────────────────────────────────────
//
// Seekbar dengan tape-scrub:
//   • Selama drag  → seek dikirim ke native setiap ≥100 ms (timestamp throttle,
//                    tidak ada Timer background — aman untuk gesture recognizer)
//   • Selesai drag → seek tepat ke posisi akhir, pulihkan speed
//   • Speed boost  → saat drag cepat (>3 s-audio/s-nyata) speed sementara naik
//                    maks 2×; tidak disimpan ke prefs
//
// UI/visual identik dengan versi sebelumnya — tidak ada perubahan tampilan.

class PlayerProgressSection extends StatefulWidget {
  final String Function(Duration duration) formatTime;

  const PlayerProgressSection({
    super.key,
    required this.formatTime,
  });

  @override
  State<PlayerProgressSection> createState() => _PlayerProgressSectionState();
}

class _PlayerProgressSectionState extends State<PlayerProgressSection> {
  // ── Drag state ─────────────────────────────────────────────────────────────
  bool _isDragging = false;
  double _dragValue = 0.0;

  // ── Throttle: timestamp-based, no background timer ─────────────────────────
  int _lastSeekMs = 0;
  static const int _throttleMs = 100;

  // ── Speed modulation ───────────────────────────────────────────────────────
  double _savedSpeed = 1.0;
  double _currentScrubSpeed = 1.0;
  double _velPrevValue = 0.0;
  int _velPrevMs = 0;

  // ── Callbacks ──────────────────────────────────────────────────────────────

  void _onChangeStart(double startValue) {
    _savedSpeed = AudioEffectsService.playbackSpeed.value;
    _currentScrubSpeed = _savedSpeed;
    _velPrevValue = startValue;
    _velPrevMs = DateTime.now().millisecondsSinceEpoch;
    _lastSeekMs = 0; // force seek to be sent on first drag move

    setState(() {
      _isDragging = true;
      _dragValue = startValue;
    });
  }

  void _onChanged(double newValue) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // ── Velocity → speed boost ───────────────────────────────────────────────
    final dt = nowMs - _velPrevMs;
    if (dt > 0 && dt < 500) {
      final vel = (newValue - _velPrevValue).abs() / (dt / 1000.0);
      _updateScrubSpeed(vel);
    }
    _velPrevValue = newValue;
    _velPrevMs = nowMs;

    // ── Throttled seek (timestamp-based, no Timer) ───────────────────────────
    if (nowMs - _lastSeekMs >= _throttleMs) {
      _lastSeekMs = nowMs;
      AudioService.seek(Duration(milliseconds: (newValue * 1000).round()));
    }

    setState(() => _dragValue = newValue);
  }

  void _onChangeEnd(double endValue) {
    // Restore speed if it was boosted
    if ((_currentScrubSpeed - _savedSpeed).abs() > 0.01) {
      AudioService.clearScrubSpeed();
    }

    // Final authoritative seek (millisecond precision)
    AudioService.seek(Duration(milliseconds: (endValue * 1000).round()));

    setState(() {
      _isDragging = false;
      _currentScrubSpeed = _savedSpeed;
    });
  }

  // ── Speed helper ───────────────────────────────────────────────────────────

  /// Sesuaikan speed sementara berdasarkan kecepatan drag (sec-audio / sec-nyata).
  /// • vel < 3 → tidak ada boost, tetap di kecepatan user
  /// • vel ≥ 3 → naik proporsional, maks 2× dari kecepatan user
  /// Hanya mengirim MethodChannel jika target berbeda ≥0.2 (hindari spam).
  void _updateScrubSpeed(double vel) {
    final target = vel < 3.0
        ? _savedSpeed
        : (_savedSpeed * vel / 3.0).clamp(_savedSpeed, 2.0);

    if ((target - _currentScrubSpeed).abs() >= 0.2) {
      _currentScrubSpeed = target;
      AudioService.setTemporaryScrubSpeed(target);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  //
  // Widget tree identik dengan versi sebelumnya.

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: AudioService.playbackState,
      builder: (context, state, _) {
        final position = state.position;
        final duration = state.duration;
        final durationSeconds = duration.inSeconds;

        final liveValue = durationSeconds == 0
            ? 0.0
            : position.inSeconds
                .clamp(0, durationSeconds)
                .toDouble();

        final displayValue = _isDragging ? _dragValue : liveValue;

        final displayPosition = _isDragging
            ? Duration(seconds: _dragValue.toInt())
            : position;

        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 6,
                activeTrackColor: Colors.white,
                inactiveTrackColor: const Color(0xFF808080),
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 0,
                  disabledThumbRadius: 0,
                ),
                overlayShape: SliderComponentShape.noOverlay,
                thumbColor: Colors.transparent,
                overlayColor: Colors.transparent,
              ),
              child: Slider(
                min: 0,
                max: durationSeconds == 0 ? 1 : durationSeconds.toDouble(),
                value: displayValue,
                onChangeStart: durationSeconds == 0 ? null : _onChangeStart,
                onChanged:     durationSeconds == 0 ? null : _onChanged,
                onChangeEnd:   durationSeconds == 0 ? null : _onChangeEnd,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.formatTime(displayPosition),
                  style: const TextStyle(
                    fontWeight: FontWeight.w400,
                    fontSize: 11,
                    color: Colors.white70,
                  ),
                ),
                Text(
                  '-${widget.formatTime(duration - displayPosition)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w400,
                    fontSize: 11,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
