import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../../services/audio_service.dart';
import '../../services/audio/audio_effects_service.dart';
import '../../utils/safe_num.dart';

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
class AppleMusicSliderTrackShape extends SliderTrackShape {
  const AppleMusicSliderTrackShape();

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final trackHeight = sliderTheme.trackHeight ?? 6;

    return Rect.fromLTWH(
      offset.dx,
      offset.dy + (parentBox.size.height - trackHeight) / 2,
      parentBox.size.width,
      trackHeight,
    );
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
    Offset? secondaryOffset,
  }) {
    final canvas = context.canvas;

    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final radius = Radius.circular(trackRect.height / 2);

    // gambar full track dulu
    canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, radius),
      Paint()..color = sliderTheme.inactiveTrackColor!,
    );

    // gambar progress aktif di atasnya
    final activeRect = Rect.fromLTRB(
      trackRect.left,
      trackRect.top,
      thumbCenter.dx.clamp(trackRect.left, trackRect.right),
      trackRect.bottom,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(activeRect, radius),
      Paint()..color = sliderTheme.activeTrackColor!,
    );
  }
}

class PlayerProgressSection extends StatefulWidget {
  final String Function(Duration duration) formatTime;

  const PlayerProgressSection({super.key, required this.formatTime});

  @override
  State<PlayerProgressSection> createState() => _PlayerProgressSectionState();
}

class _PlayerProgressSectionState extends State<PlayerProgressSection> {
  // Shared SliderThemeData — computed once instead of on every ~50 ms
  // playback-state rebuild.  All values are const so this is safe to cache.
  static final _sliderTheme = SliderThemeData(
    trackHeight: 6, // 7 default
    trackShape: const AppleMusicSliderTrackShape(),
    activeTrackColor: Colors.white.withValues(alpha: 1.0),
    inactiveTrackColor: const Color(0xFF8D8D8D).withValues(alpha: 1.0),
    thumbShape: const RoundSliderThumbShape(
      enabledThumbRadius: 0,
      disabledThumbRadius: 0,
    ),
    overlayShape: SliderComponentShape.noOverlay,
    thumbColor: Colors.transparent,
    overlayColor: Colors.transparent,
  );

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
      unawaited(
        AudioService.seek(Duration(milliseconds: (newValue * 1000).round())),
      );
    }

    setState(() => _dragValue = newValue);
  }

  void _onChangeEnd(double endValue) {
    // Restore speed if it was boosted
    if ((_currentScrubSpeed - _savedSpeed).abs() > 0.01) {
      unawaited(AudioService.clearScrubSpeed());
    }

    // Final authoritative seek (millisecond precision)
    unawaited(
      AudioService.seek(Duration(milliseconds: (endValue * 1000).round())),
    );

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
      unawaited(AudioService.setTemporaryScrubSpeed(target));
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
            : position.inSeconds.clamp(0, durationSeconds).toDouble();

        final displayValue = _isDragging ? _dragValue : liveValue;

        final displayPosition = _isDragging
            ? Duration(seconds: _dragValue.toIntOrElse(0))
            : position;

        return Column(
          children: [
            SizedBox(
              height: 32,
              child: Center(
                child: SliderTheme(
                  data: _sliderTheme,
                  child: Slider(
                    min: 0,
                    max: durationSeconds == 0 ? 1 : durationSeconds.toDouble(),
                    value: displayValue,
                    onChangeStart: durationSeconds == 0 ? null : _onChangeStart,
                    onChanged: durationSeconds == 0 ? null : _onChanged,
                    onChangeEnd: durationSeconds == 0 ? null : _onChangeEnd,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 1),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.formatTime(displayPosition),
                  style: const TextStyle(
                    fontWeight: FontWeight.w400,
                    fontSize: 12,
                    color: Colors.white38,
                  ),
                ),
                Text(
                  '-${widget.formatTime(duration - displayPosition)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w400,
                    fontSize: 12,
                    color: Colors.white38,
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
