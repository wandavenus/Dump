import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/audio_service.dart';
import '../../services/audio/audio_effects_service.dart';

// ─── PlayerProgressSection ────────────────────────────────────────────────────
//
// Seekbar dengan tape-scrub:
//   • Saat drag dimulai  → seek langsung ke posisi, mulai throttle timer
//   • Selama drag        → kirim seek setiap 100 ms (throttle); jika drag
//                          cepat (>3 detik-audio/detik-nyata) naikkan speed
//                          sementara ke maks 2× tanpa menyimpan ke prefs
//   • Saat drag selesai → seek tepat ke posisi akhir, pulihkan speed asli
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
  // ── Scrub state ────────────────────────────────────────────────────────────
  bool _isDragging = false;
  double _dragValue = 0.0;

  /// Timer yang mengirim seek ke native setiap 100 ms selama drag.
  Timer? _scrubTimer;

  /// Nilai terakhir yang BELUM dikirim ke native — diperbarui setiap frame drag.
  double _pendingSec = 0.0;

  /// Apakah ada nilai baru yang menunggu dikirim sejak flush terakhir.
  bool _seekDirty = false;

  /// Kecepatan yang tersimpan pengguna — dipulihkan setelah scrub.
  double _savedSpeed = 1.0;

  /// Kecepatan scrub aktif saat ini (untuk mendeteksi perubahan).
  double _activeScrubSpeed = 1.0;

  // ── Velocity tracking ──────────────────────────────────────────────────────
  double _velDragPrev = 0.0;
  int _velTimePrevMs = 0;

  // ── Constants ──────────────────────────────────────────────────────────────
  static const int _throttleMs = 100;   // max 10 seeks/detik
  static const double _velThreshold = 3.0;   // sec-audio/detik sebelum boost
  static const double _maxScrubSpeed = 2.0;  // batas atas speed boost

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _cancelTimer();
    super.dispose();
  }

  void _cancelTimer() {
    _scrubTimer?.cancel();
    _scrubTimer = null;
  }

  // ── Scrub handlers ─────────────────────────────────────────────────────────

  void _onChangeStart(double startValue) {
    _savedSpeed    = AudioEffectsService.playbackSpeed.value;
    _activeScrubSpeed = _savedSpeed;
    _pendingSec    = startValue;
    _seekDirty     = true;
    _velDragPrev   = startValue;
    _velTimePrevMs = DateTime.now().millisecondsSinceEpoch;

    setState(() {
      _isDragging = true;
      _dragValue  = startValue;
    });

    // Haptic feedback: subtle selection click saat mulai drag
    HapticFeedback.selectionClick();

    // Langsung seek ke titik yang disentuh
    _sendSeek(startValue);

    // Mulai throttle timer untuk seek selama drag
    _scrubTimer = Timer.periodic(
      const Duration(milliseconds: _throttleMs),
      (_) => _flushSeek(),
    );
  }

  void _onChanged(double newValue) {
    // Hitung velocity drag (audio-seconds per real-second)
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final deltaMs = nowMs - _velTimePrevMs;
    if (deltaMs > 0) {
      final velocity = (newValue - _velDragPrev).abs() / (deltaMs / 1000.0);
      _updateScrubSpeed(velocity);
      _velDragPrev   = newValue;
      _velTimePrevMs = nowMs;
    }

    _pendingSec = newValue;
    _seekDirty  = true;

    setState(() => _dragValue = newValue);
  }

  void _onChangeEnd(double endValue) {
    _cancelTimer();

    // Seek tepat ke posisi akhir (milli-second precision)
    _sendSeek(endValue);

    // Pulihkan speed asli tanpa menyentuh AudioEffectsService (tidak persist)
    if ((_activeScrubSpeed - _savedSpeed).abs() > 0.01) {
      AudioService.clearScrubSpeed();
    }

    // Haptic ringan saat jari diangkat
    HapticFeedback.lightImpact();

    setState(() {
      _isDragging       = false;
      _activeScrubSpeed = _savedSpeed;
    });
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Kirim seek ke native dengan presisi milidetik.
  void _sendSeek(double seconds) {
    AudioService.seek(Duration(milliseconds: (seconds * 1000).round()));
  }

  /// Dipanggil oleh timer setiap 100 ms — hanya kirim jika ada perubahan baru.
  void _flushSeek() {
    if (!mounted || !_isDragging) return;
    if (!_seekDirty) return;
    _seekDirty = false;
    _sendSeek(_pendingSec);
  }

  /// Sesuaikan speed sementara berdasarkan kecepatan drag.
  ///
  /// Rumus: jika velocity < threshold → speed = savedSpeed (tidak berubah)
  ///        jika velocity ≥ threshold → speed = min(savedSpeed * velocity / threshold, 2×)
  ///
  /// Hanya kirim ke native jika target berbeda >0.15 dari saat ini.
  void _updateScrubSpeed(double velocity) {
    final double target;
    if (velocity < _velThreshold) {
      target = _savedSpeed;
    } else {
      target = (_savedSpeed * velocity / _velThreshold).clamp(
        _savedSpeed,
        _maxScrubSpeed,
      );
    }

    if ((target - _activeScrubSpeed).abs() > 0.15) {
      _activeScrubSpeed = target;
      AudioService.setTemporaryScrubSpeed(target);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  //
  // UI identik dengan versi sebelumnya — tidak ada perubahan tampilan.

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

        final displayValue    = _isDragging ? _dragValue  : liveValue;
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
