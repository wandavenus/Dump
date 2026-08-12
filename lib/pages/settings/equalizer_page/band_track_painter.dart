part of '../equalizer_page.dart';

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
    required this.trackBg,
    required this.centerTickColor,
    required this.disabledAccentColor,
    required this.accentColor,
    required this.neutralTrackColor,
  });

  final double gain;
  final double min;
  final double max;
  final double pressAmount;
  final bool enabled;
  final Color trackBg;
  final Color centerTickColor;
  final Color disabledAccentColor;
  final Color accentColor;
  final Color neutralTrackColor;

  static const _trackW = 3.0;
  static const _thumbBaseR = 7.0;
  static const _thumbPressExtra = 2.5;
  static const _centerTickHalfW = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    final range = max - min;
    if (range <= 0) return;

    final cx = size.width / 2;
    final gainFraction = (gain - min) / range; // 0.0 (min) → 1.0 (max)
    final zeroFraction = (-min) / range; // position of 0 dB
    final thumbY = size.height * (1.0 - gainFraction);
    final centerY = size.height * (1.0 - zeroFraction);

    // ── Colours ──────────────────────────────────────────────────────────────
    final activeColor = enabled
        ? Color.lerp(
            neutralTrackColor,
            accentColor,
            (gain.abs() / (range / 2)).clamp(0.0, 1.0),
          )!
        : disabledAccentColor;
    final thumbColor = enabled
        ? Color.lerp(
            neutralTrackColor,
            accentColor,
            (gain.abs() / (range / 2)).clamp(0.0, 1.0) * 0.8 +
                pressAmount * 0.2,
          )!
        : disabledAccentColor;

    // ── Background track ─────────────────────────────────────────────────────
    final bgPaint = Paint()
      ..color = trackBg
      ..strokeWidth = _trackW
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), bgPaint);

    // ── Active fill (center → thumb) ─────────────────────────────────────────
    if (gain.abs() > 0.05) {
      final activePaint = Paint()
        ..color = activeColor
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
      ..color = centerTickColor
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(cx - _centerTickHalfW, centerY),
      Offset(cx + _centerTickHalfW, centerY),
      centerPaint,
    );

    // ── Thumb glow (when pressed or gain ≠ 0) ────────────────────────────────
    final glowOpacity = (pressAmount * 0.25 + (gain.abs() > 0.1 ? 0.08 : 0.0));
    if (glowOpacity > 0 && enabled) {
      final glowPaint = Paint()
        ..color = accentColor.withValues(alpha: glowOpacity)
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
      old.max != max ||
      old.trackBg != trackBg ||
      old.centerTickColor != centerTickColor ||
      old.disabledAccentColor != disabledAccentColor;
}
