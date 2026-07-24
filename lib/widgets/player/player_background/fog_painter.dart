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
//   • Both setColors() and advanceBlend() immediately recompute the 15
//     pre-interpolated colour floats (_c0r … _c4b) so paint() performs no
//     arithmetic at all — just 18 setFloat() calls and 1 drawRect().
//   • Rapid song skips are handled correctly: setColors() always captures the
//     mid-transition interpolated position so there is no visual snap.
//
// Uniform layout (matches fluid.frag declaration order):
//   0-1   uSize       canvas size
//   2     uTime       monotonic seconds
//   3-5   uColor0     primary   (colors[0])
//   6-8   uColor1     secondary (colors[1])
//   9-11  uColor2     accent    (colors[2])
//   12-14 uHighlight  highlight (colors[3])
//   15-17 uShadow     shadow    (colors[4])
//
// Per-frame cost:
//   • 0 lerps in paint() + 18 setFloat() calls + 1 drawRect() — negligible.
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
  // Colors[0]=primary, [1]=secondary, [2]=accent, [3]=highlight, [4]=shadow.

  double _old0r = 43 / 255.0,  _old0g = 49 / 255.0,  _old0b = 58 / 255.0;
  double _old1r = 78 / 255.0,  _old1g = 101 / 255.0, _old1b = 125 / 255.0;
  double _old2r = 123 / 255.0, _old2g = 135 / 255.0, _old2b = 148 / 255.0;
  double _old3r = 171 / 255.0, _old3g = 190 / 255.0, _old3b = 212 / 255.0; // highlight fallback
  double _old4r = 18 / 255.0,  _old4g = 24 / 255.0,  _old4b = 33 / 255.0;  // shadow fallback

  double _cur0r = 43 / 255.0,  _cur0g = 49 / 255.0,  _cur0b = 58 / 255.0;
  double _cur1r = 78 / 255.0,  _cur1g = 101 / 255.0, _cur1b = 125 / 255.0;
  double _cur2r = 123 / 255.0, _cur2g = 135 / 255.0, _cur2b = 148 / 255.0;
  double _cur3r = 171 / 255.0, _cur3g = 190 / 255.0, _cur3b = 212 / 255.0;
  double _cur4r = 18 / 255.0,  _cur4g = 24 / 255.0,  _cur4b = 33 / 255.0;

  // ── Pre-computed interpolated colours (written by _recompute, read by paint)
  // Initialised to the fallback palette so paint() is safe before the first
  // setColors() call.
  double _c0r = 43 / 255.0,  _c0g = 49 / 255.0,  _c0b = 58 / 255.0;
  double _c1r = 78 / 255.0,  _c1g = 101 / 255.0, _c1b = 125 / 255.0;
  double _c2r = 123 / 255.0, _c2g = 135 / 255.0, _c2b = 148 / 255.0;
  double _c3r = 171 / 255.0, _c3g = 190 / 255.0, _c3b = 212 / 255.0;
  double _c4r = 18 / 255.0,  _c4g = 24 / 255.0,  _c4b = 33 / 255.0;

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  /// Recomputes the 15 pre-interpolated floats from the current _blend value.
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
    _c3r = _lerp(_old3r, _cur3r, b);
    _c3g = _lerp(_old3g, _cur3g, b);
    _c3b = _lerp(_old3b, _cur3b, b);
    _c4r = _lerp(_old4r, _cur4r, b);
    _c4g = _lerp(_old4g, _cur4g, b);
    _c4b = _lerp(_old4b, _cur4b, b);
  }

  /// Called once per song change.  Captures the current interpolated position
  /// as the new baseline so rapid skips never cause a colour snap.
  void setColors(List<Color> colors) {
    // Snapshot current interpolated position → new "old" baseline.
    _old0r = _c0r; _old0g = _c0g; _old0b = _c0b;
    _old1r = _c1r; _old1g = _c1g; _old1b = _c1b;
    _old2r = _c2r; _old2g = _c2g; _old2b = _c2b;
    _old3r = _c3r; _old3g = _c3g; _old3b = _c3b;
    _old4r = _c4r; _old4g = _c4g; _old4b = _c4b;

    // Set new target colours (palette now provides 5 entries).
    final c0 = colors[0]; // primary
    final c1 = colors[1]; // secondary
    final c2 = colors[2]; // accent
    final c3 = colors.length > 3 ? colors[3] : colors[0]; // highlight
    final c4 = colors.length > 4 ? colors[4] : colors[0]; // shadow
    _cur0r = c0.r; _cur0g = c0.g; _cur0b = c0.b;
    _cur1r = c1.r; _cur1g = c1.g; _cur1b = c1.b;
    _cur2r = c2.r; _cur2g = c2.g; _cur2b = c2.b;
    _cur3r = c3.r; _cur3g = c3.g; _cur3b = c3.b;
    _cur4r = c4.r; _cur4g = c4.g; _cur4b = c4.b;

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
      ..setFloat(3, _c0r)   // uColor0.r    primary
      ..setFloat(4, _c0g)   // uColor0.g
      ..setFloat(5, _c0b)   // uColor0.b
      ..setFloat(6, _c1r)   // uColor1.r    secondary
      ..setFloat(7, _c1g)   // uColor1.g
      ..setFloat(8, _c1b)   // uColor1.b
      ..setFloat(9, _c2r)   // uColor2.r    accent
      ..setFloat(10, _c2g)  // uColor2.g
      ..setFloat(11, _c2b)  // uColor2.b
      ..setFloat(12, _c3r)  // uHighlight.r highlight
      ..setFloat(13, _c3g)  // uHighlight.g
      ..setFloat(14, _c3b)  // uHighlight.b
      ..setFloat(15, _c4r)  // uShadow.r    shadow
      ..setFloat(16, _c4g)  // uShadow.g
      ..setFloat(17, _c4b); // uShadow.b

    _paint.shader = shader;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), _paint);
  }

  @override
  bool shouldRepaint(_ShaderPainter old) => true;
}
