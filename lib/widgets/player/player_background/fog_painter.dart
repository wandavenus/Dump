part of '../player_background.dart';

// ─────────────────────────────────────────────────────────────────────────────
// _ShaderPainter
//
// CustomPainter that renders the fluid.frag GLSL shader.
//
// Colour crossfade:
//   • setColors() is called once per song change.  It captures the current
//     interpolated position as the new "old" baseline and starts _blend at 0.
//   • advanceBlend(realDt) is called every animation tick by the owning State.
//     It increments _blend toward 1 over _kBlendDuration seconds.
//   • paint() lerps old→new colours using _blend before pushing floats to the
//     shader — zero GPU overhead, trivial Dart arithmetic.
//   • Rapid song skips are handled correctly: setColors() always captures the
//     mid-transition interpolated position so there is no visual snap.
//
// Per-frame cost:
//   • 9 lerps (doubles) + 12 setFloat() calls + 1 drawRect() — negligible.
//   • All heavy work (trig × 131 072 pixels) runs on the GPU.
// ─────────────────────────────────────────────────────────────────────────────

class _ShaderPainter extends CustomPainter {
  _ShaderPainter({required this.shader, required Listenable repaint})
    : super(repaint: repaint);

  final ui.FragmentShader shader;

  // Crossfade duration in real seconds (matches dt units from _onTick).
  static const double _kBlendDuration = 0.8;

  // ── Per-frame state ───────────────────────────────────────────────────────

  double _time = 0.0;
  double _blend = 1.0; // 0 = fully old, 1 = fully new

  void setTime(double t) => _time = t;

  /// Advance colour crossfade.  [realDt] is elapsed time in real seconds.
  void advanceBlend(double realDt) {
    if (_blend < 1.0) {
      _blend = (_blend + realDt / _kBlendDuration).clamp(0.0, 1.0);
    }
  }

  // ── Per-song colour state ─────────────────────────────────────────────────
  // "Old" = colour set we are fading from (updated at every setColors call).
  // "Cur" = colour set we are fading toward.
  // Fallback: dark navy tones used before the first extraction completes.

  double _old0r = 43 / 255.0, _old0g = 49 / 255.0, _old0b = 58 / 255.0;
  double _old1r = 78 / 255.0, _old1g = 101 / 255.0, _old1b = 125 / 255.0;
  double _old2r = 123 / 255.0, _old2g = 135 / 255.0, _old2b = 148 / 255.0;

  double _cur0r = 43 / 255.0, _cur0g = 49 / 255.0, _cur0b = 58 / 255.0;
  double _cur1r = 78 / 255.0, _cur1g = 101 / 255.0, _cur1b = 125 / 255.0;
  double _cur2r = 123 / 255.0, _cur2g = 135 / 255.0, _cur2b = 148 / 255.0;

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  /// Called once per song change.  Captures the current interpolated position
  /// as the new baseline so rapid skips never cause a colour snap.
  void setColors(List<Color> colors) {
    // Snapshot current interpolated position → new "old" baseline.
    final b = _blend;
    _old0r = _lerp(_old0r, _cur0r, b);
    _old0g = _lerp(_old0g, _cur0g, b);
    _old0b = _lerp(_old0b, _cur0b, b);
    _old1r = _lerp(_old1r, _cur1r, b);
    _old1g = _lerp(_old1g, _cur1g, b);
    _old1b = _lerp(_old1b, _cur1b, b);
    _old2r = _lerp(_old2r, _cur2r, b);
    _old2g = _lerp(_old2g, _cur2g, b);
    _old2b = _lerp(_old2b, _cur2b, b);

    // Set new target colours.
    final c0 = colors[0];
    final c1 = colors[1];
    final c2 = colors[2];
    _cur0r = c0.r;
    _cur0g = c0.g;
    _cur0b = c0.b;
    _cur1r = c1.r;
    _cur1g = c1.g;
    _cur1b = c1.b;
    _cur2r = c2.r;
    _cur2g = c2.g;
    _cur2b = c2.b;

    // Restart the crossfade from 0.
    _blend = 0.0;
  }

  // ── CustomPainter ─────────────────────────────────────────────────────────

  final _paint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    // Interpolate between old and new colour sets using current blend progress.
    final b = _blend;

    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, _time)
      ..setFloat(3, _lerp(_old0r, _cur0r, b)) // uColor0.r
      ..setFloat(4, _lerp(_old0g, _cur0g, b)) // uColor0.g
      ..setFloat(5, _lerp(_old0b, _cur0b, b)) // uColor0.b
      ..setFloat(6, _lerp(_old1r, _cur1r, b)) // uColor1.r
      ..setFloat(7, _lerp(_old1g, _cur1g, b)) // uColor1.g
      ..setFloat(8, _lerp(_old1b, _cur1b, b)) // uColor1.b
      ..setFloat(9, _lerp(_old2r, _cur2r, b)) // uColor2.r
      ..setFloat(10, _lerp(_old2g, _cur2g, b)) // uColor2.g
      ..setFloat(11, _lerp(_old2b, _cur2b, b)); // uColor2.b

    _paint.shader = shader;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), _paint);
  }

  @override
  bool shouldRepaint(_ShaderPainter old) => true;
}
