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
//   • Both setColors() and advanceBlend() immediately recompute the 9
//     pre-interpolated colour floats (_c0r … _c2b) so paint() performs no
//     arithmetic at all — just 12 setFloat() calls and 1 drawRect().
//   • Rapid song skips are handled correctly: setColors() always captures the
//     mid-transition interpolated position so there is no visual snap.
//
// Per-frame cost:
//   • 0 lerps in paint() + 12 setFloat() calls + 1 drawRect() — negligible.
//   • All heavy work (trig × 131 072 pixels) runs on the GPU.
//   • Lerp arithmetic is paid at most once per tick (in advanceBlend), and
//     only while a crossfade is in progress; it is skipped once blend = 1.
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
  /// Pre-computes the interpolated colour floats when blend actually changes so
  /// paint() has zero arithmetic to do.
  void advanceBlend(double realDt) {
    if (_blend < 1.0) {
      _blend = (_blend + realDt / _kBlendDuration).clamp(0.0, 1.0);
      _recompute();
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

  // ── Pre-computed interpolated colours (written by _recompute, read by paint)
  // Initialised to the fallback palette so paint() is safe before the first
  // setColors() call.
  double _c0r = 43 / 255.0, _c0g = 49 / 255.0, _c0b = 58 / 255.0;
  double _c1r = 78 / 255.0, _c1g = 101 / 255.0, _c1b = 125 / 255.0;
  double _c2r = 123 / 255.0, _c2g = 135 / 255.0, _c2b = 148 / 255.0;

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  /// Recomputes the 9 pre-interpolated floats from the current _blend value.
  /// Called by setColors() and advanceBlend() — never by paint().
  void _recompute() {
    final b = _blend;
    _c0r = _lerp(_old0r, _cur0r, b);
    _c0g = _lerp(_old0g, _cur0g, b);
    _c0b = _lerp(_old0b, _cur0b, b);
    _c1r = _lerp(_old1r, _cur1r, b);
    _c1g = _lerp(_old1g, _cur1g, b);
    _c1b = _lerp(_old1b, _cur1b, b);
    _c2r = _lerp(_old2r, _cur2r, b);
    _c2g = _lerp(_old2g, _cur2g, b);
    _c2b = _lerp(_old2b, _cur2b, b);
  }

  /// Called once per song change.  Captures the current interpolated position
  /// as the new baseline so rapid skips never cause a colour snap.
  void setColors(List<Color> colors) {
    // Snapshot current interpolated position → new "old" baseline.
    _old0r = _c0r; _old0g = _c0g; _old0b = _c0b;
    _old1r = _c1r; _old1g = _c1g; _old1b = _c1b;
    _old2r = _c2r; _old2g = _c2g; _old2b = _c2b;

    // Set new target colours.
    final c0 = colors[0];
    final c1 = colors[1];
    final c2 = colors[2];
    _cur0r = c0.r; _cur0g = c0.g; _cur0b = c0.b;
    _cur1r = c1.r; _cur1g = c1.g; _cur1b = c1.b;
    _cur2r = c2.r; _cur2g = c2.g; _cur2b = c2.b;

    // Restart the crossfade from 0 and pre-compute the starting position
    // (blend=0 means the pre-computed values equal the old baseline).
    _blend = 0.0;
    _recompute();
  }

  // ── CustomPainter ─────────────────────────────────────────────────────────

  final _paint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    // Pre-computed colour floats — no arithmetic here.
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, _time)
      ..setFloat(3, _c0r)  // uColor0.r
      ..setFloat(4, _c0g)  // uColor0.g
      ..setFloat(5, _c0b)  // uColor0.b
      ..setFloat(6, _c1r)  // uColor1.r
      ..setFloat(7, _c1g)  // uColor1.g
      ..setFloat(8, _c1b)  // uColor1.b
      ..setFloat(9, _c2r)  // uColor2.r
      ..setFloat(10, _c2g) // uColor2.g
      ..setFloat(11, _c2b); // uColor2.b

    _paint.shader = shader;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), _paint);
  }

  @override
  bool shouldRepaint(_ShaderPainter old) => true;
}
