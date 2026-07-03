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
  _ShaderPainter({
    required this.shader,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final ui.FragmentShader shader;

  // Crossfade duration in real seconds (matches dt units from _onTick).
  static const double _kBlendDuration = 0.8;

  // ── Per-frame state ───────────────────────────────────────────────────────

  double _time  = 0.0;
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

  double _o0r = 43 / 255.0, _o0g = 49 / 255.0, _o0b = 58 / 255.0;
double _o1r = 78 / 255.0, _o1g = 101 / 255.0, _o1b = 125 / 255.0;
double _o2r = 123 / 255.0, _o2g = 135 / 255.0, _o2b = 148 / 255.0;

double _c0r = 43 / 255.0, _c0g = 49 / 255.0, _c0b = 58 / 255.0;
double _c1r = 78 / 255.0, _c1g = 101 / 255.0, _c1b = 125 / 255.0;
double _c2r = 123 / 255.0, _c2g = 135 / 255.0, _c2b = 148 / 255.0;

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  /// Called once per song change.  Captures the current interpolated position
  /// as the new baseline so rapid skips never cause a colour snap.
  void setColors(List<Color> colors) {
    // Snapshot current interpolated position → new "old" baseline.
    final b = _blend;
    _o0r = _lerp(_o0r, _c0r, b);  _o0g = _lerp(_o0g, _c0g, b);  _o0b = _lerp(_o0b, _c0b, b);
    _o1r = _lerp(_o1r, _c1r, b);  _o1g = _lerp(_o1g, _c1g, b);  _o1b = _lerp(_o1b, _c1b, b);
    _o2r = _lerp(_o2r, _c2r, b);  _o2g = _lerp(_o2g, _c2g, b);  _o2b = _lerp(_o2b, _c2b, b);

    // Set new target colours.
    final c0 = colors[0];
    final c1 = colors[1];
    final c2 = colors[2];
    _c0r = c0.red   / 255.0;  _c0g = c0.green / 255.0;  _c0b = c0.blue / 255.0;
    _c1r = c1.red   / 255.0;  _c1g = c1.green / 255.0;  _c1b = c1.blue / 255.0;
    _c2r = c2.red   / 255.0;  _c2g = c2.green / 255.0;  _c2b = c2.blue / 255.0;

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
      ..setFloat(0,  size.width)
      ..setFloat(1,  size.height)
      ..setFloat(2,  _time)
      ..setFloat(3,  _lerp(_o0r, _c0r, b))   // uColor0.r
      ..setFloat(4,  _lerp(_o0g, _c0g, b))   // uColor0.g
      ..setFloat(5,  _lerp(_o0b, _c0b, b))   // uColor0.b
      ..setFloat(6,  _lerp(_o1r, _c1r, b))   // uColor1.r
      ..setFloat(7,  _lerp(_o1g, _c1g, b))   // uColor1.g
      ..setFloat(8,  _lerp(_o1b, _c1b, b))   // uColor1.b
      ..setFloat(9,  _lerp(_o2r, _c2r, b))   // uColor2.r
      ..setFloat(10, _lerp(_o2g, _c2g, b))   // uColor2.g
      ..setFloat(11, _lerp(_o2b, _c2b, b));  // uColor2.b

    _paint.shader = shader;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      _paint,
    );
  }

  @override
  bool shouldRepaint(_ShaderPainter old) => true;
}
