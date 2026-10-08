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
//     lerps.
//   • Rapid song skips are handled correctly: setColors() always captures the
//     mid-transition interpolated position so there is no visual snap.
//
// Time-dependent shader work (F4 fix):
//   All values that only depend on the clock — mesh node positions, the
//   palette-rotated node colours, the ambient-shadow phase and the film-grain
//   phase — are computed here in Dart (float64) each paint and uploaded as
//   uniforms. fluid.frag no longer receives uTime, so GPU float32 precision
//   cannot degrade over long uptimes and no periodic wrap artifact exists.
//
// Uniform layout (matches fluid.frag declaration order):
//   0-1    uSize         canvas size
//   2-3    uNode0        node 0 position
//   4-5    uNode1        node 1 position
//   6-7    uNode2        node 2 position
//   8-9    uNode3        node 3 position
//   10-12  uNodeColor0   node 0 colour (palette-rotated)
//   13-15  uNodeColor1   node 1 colour
//   16-18  uNodeColor2   node 2 colour
//   19-21  uNodeColor3   node 3 colour
//   22-24  uShadow       shadow tint (ambient blend target)
//   25     uShadowPhase  (t * 0.2) mod 2π
//   26     uGrainPhase   t mod 1.0
//
// Per-frame cost:
//   • paint() runs a handful of double-precision trig calls (9 sin/cos), 27
//     setFloat() calls and 1 drawRect() — negligible on the CPU.
//   • All per-fragment work in the shader is now pure blending; time-only math
//     is never repeated across the 131,072 fragments.
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
  /// paint() has zero lerp arithmetic to do.
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

  double _old0r = 43 / 255.0, _old0g = 49 / 255.0, _old0b = 58 / 255.0;
  double _old1r = 78 / 255.0, _old1g = 101 / 255.0, _old1b = 125 / 255.0;
  double _old2r = 123 / 255.0, _old2g = 135 / 255.0, _old2b = 148 / 255.0;
  double _old3r = 171 / 255.0,
      _old3g = 190 / 255.0,
      _old3b = 212 / 255.0; // highlight fallback
  double _old4r = 18 / 255.0,
      _old4g = 24 / 255.0,
      _old4b = 33 / 255.0; // shadow fallback

  double _cur0r = 43 / 255.0, _cur0g = 49 / 255.0, _cur0b = 58 / 255.0;
  double _cur1r = 78 / 255.0, _cur1g = 101 / 255.0, _cur1b = 125 / 255.0;
  double _cur2r = 123 / 255.0, _cur2g = 135 / 255.0, _cur2b = 148 / 255.0;
  double _cur3r = 171 / 255.0, _cur3g = 190 / 255.0, _cur3b = 212 / 255.0;
  double _cur4r = 18 / 255.0, _cur4g = 24 / 255.0, _cur4b = 33 / 255.0;

  // ── Pre-computed interpolated colours (written by _recompute, read by paint)
  // Initialised to the fallback palette so paint() is safe before the first
  // setColors() call.
  double _c0r = 43 / 255.0, _c0g = 49 / 255.0, _c0b = 58 / 255.0;
  double _c1r = 78 / 255.0, _c1g = 101 / 255.0, _c1b = 125 / 255.0;
  double _c2r = 123 / 255.0, _c2g = 135 / 255.0, _c2b = 148 / 255.0;
  double _c3r = 171 / 255.0, _c3g = 190 / 255.0, _c3b = 212 / 255.0;
  double _c4r = 18 / 255.0, _c4g = 24 / 255.0, _c4b = 33 / 255.0;

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
    _old0r = _c0r;
    _old0g = _c0g;
    _old0b = _c0b;
    _old1r = _c1r;
    _old1g = _c1g;
    _old1b = _c1b;
    _old2r = _c2r;
    _old2g = _c2g;
    _old2b = _c2b;
    _old3r = _c3r;
    _old3g = _c3g;
    _old3b = _c3b;
    _old4r = _c4r;
    _old4g = _c4g;
    _old4b = _c4b;

    // Set new target colours — NativePaletteService._padToFive() guarantees
    // exactly 5 entries; guard all indices defensively with semantically correct
    // fallback tones (not colors[0]) in case the contract is ever violated.
    final c0 = colors.isNotEmpty
        ? colors[0]
        : const Color(0xFF2B313A); // primary
    final c1 = colors.length > 1
        ? colors[1]
        : const Color(0xFF4E657D); // secondary
    final c2 = colors.length > 2
        ? colors[2]
        : const Color(0xFF7B8794); // accent
    final c3 = colors.length > 3
        ? colors[3]
        : const Color(0xFFABBED4); // highlight
    final c4 = colors.length > 4
        ? colors[4]
        : const Color(0xFF121821); // shadow
    _cur0r = c0.r;
    _cur0g = c0.g;
    _cur0b = c0.b;
    _cur1r = c1.r;
    _cur1g = c1.g;
    _cur1b = c1.b;
    _cur2r = c2.r;
    _cur2g = c2.g;
    _cur2b = c2.b;
    _cur3r = c3.r;
    _cur3g = c3.g;
    _cur3b = c3.b;
    _cur4r = c4.r;
    _cur4g = c4.g;
    _cur4b = c4.b;

    // Restart the crossfade from 0 and pre-compute the starting position
    // (blend=0 means the pre-computed values equal the old baseline).
    _blend = 0.0;
    _recompute();
  }

  // ── CustomPainter ─────────────────────────────────────────────────────────

  final _paint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    final t = _time;

    // Current interpolated palette (mirrors the old uniform inputs
    // uColor0 … uShadow): [0]=primary [1]=secondary [2]=accent [3]=highlight
    // [4]=shadow.
    final pal0 = [_c0r, _c0g, _c0b];
    final pal1 = [_c1r, _c1g, _c1b];
    final pal2 = [_c2r, _c2g, _c2b];
    final pal3 = [_c3r, _c3g, _c3b];
    final pal4 = [_c4r, _c4g, _c4b];

    // Mesh node positions — identical formulas to the old in-shader code.
    final n0x = 0.20 * math.sin(t * 0.11);
    final n0y = 0.20 * math.cos(t * 0.13);
    final n1x = 1.0 + 0.20 * math.cos(t * 0.09);
    final n1y = 0.20 * math.sin(t * 0.15);
    final n2x = 0.20 * math.sin(t * 0.14);
    final n2y = 1.0 + 0.20 * math.cos(t * 0.10);
    final n3x = 1.0 + 0.20 * math.cos(t * 0.12);
    final n3y = 1.0 + 0.20 * math.sin(t * 0.08);

    // Node colours — exact port of the old in-shader shiftPalette() calls.
    final c00 = _shiftPalette(t * 0.08, pal0, pal1, pal4);
    final c10 = _shiftPalette(t * 0.07 + 1.0, pal1, pal2, pal4);
    final c01 = _shiftPalette(t * 0.09 + 2.0, pal2, pal0, pal3);
    final c11 = _shiftPalette(t * 0.06 + 0.5, pal4, pal1, pal2);

    // Bounded phases keep GPU float32 sin()/fract() exact forever.
    final shadowPhase = (t * 0.2) % (2.0 * math.pi);
    final grainPhase = t - t.floorToDouble(); // t mod 1.0

    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, n0x) // uNode0
      ..setFloat(3, n0y)
      ..setFloat(4, n1x) // uNode1
      ..setFloat(5, n1y)
      ..setFloat(6, n2x) // uNode2
      ..setFloat(7, n2y)
      ..setFloat(8, n3x) // uNode3
      ..setFloat(9, n3y)
      ..setFloat(10, c00[0]) // uNodeColor0
      ..setFloat(11, c00[1])
      ..setFloat(12, c00[2])
      ..setFloat(13, c10[0]) // uNodeColor1
      ..setFloat(14, c10[1])
      ..setFloat(15, c10[2])
      ..setFloat(16, c01[0]) // uNodeColor2
      ..setFloat(17, c01[1])
      ..setFloat(18, c01[2])
      ..setFloat(19, c11[0]) // uNodeColor3
      ..setFloat(20, c11[1])
      ..setFloat(21, c11[2])
      ..setFloat(22, pal4[0]) // uShadow
      ..setFloat(23, pal4[1])
      ..setFloat(24, pal4[2])
      ..setFloat(25, shadowPhase) // uShadowPhase
      ..setFloat(26, grainPhase); // uGrainPhase

    _paint.shader = shader;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), _paint);
  }

  @override
  bool shouldRepaint(_ShaderPainter old) => true;

  // ── Helpers (exact ports of the old fluid.frag functions) ────────────────

  static double _smoothstep(double e0, double e1, double x) {
    final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
  }

  /// Port of fluid.frag's shiftPalette: 3-colour rotation with smoothstep.
  static List<double> _shiftPalette(
    double progress,
    List<double> colA,
    List<double> colB,
    List<double> colC,
  ) {
    final p = (progress * 0.333333) % 1.0 * 3.0; // fract(progress / 3) * 3
    if (p < 1.0) {
      final f = _smoothstep(0.0, 1.0, p);
      return [
        _lerp(colA[0], colB[0], f),
        _lerp(colA[1], colB[1], f),
        _lerp(colA[2], colB[2], f),
      ];
    }
    if (p < 2.0) {
      final f = _smoothstep(0.0, 1.0, p - 1.0);
      return [
        _lerp(colB[0], colC[0], f),
        _lerp(colB[1], colC[1], f),
        _lerp(colB[2], colC[2], f),
      ];
    }
    final f = _smoothstep(0.0, 1.0, p - 2.0);
    return [
      _lerp(colC[0], colA[0], f),
      _lerp(colC[1], colA[1], f),
      _lerp(colC[2], colA[2], f),
    ];
  }
}
