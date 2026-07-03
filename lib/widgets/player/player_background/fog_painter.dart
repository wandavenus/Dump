part of '../player_background.dart';

// ─────────────────────────────────────────────────────────────────────────────
// _ShaderPainter
//
// CustomPainter that renders the fluid.frag GLSL shader.
//
// Optimisation strategy:
//   • Colour values (9 floats) are pre-divided to [0, 1] range once per song
//     change via setColors() — zero division work inside paint().
//   • Only uTime (one float) changes every frame; the remaining 11 uniform
//     slots are stable until the song changes.
//   • shouldRepaint always returns true because the animation runs continuously
//     and uTime changes on every tick.
//   • The owning State reuses this painter object across frames — no
//     re-allocation per frame.
// ─────────────────────────────────────────────────────────────────────────────

class _ShaderPainter extends CustomPainter {
  _ShaderPainter({
    required this.shader,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final ui.FragmentShader shader;

  // ── Per-frame state ───────────────────────────────────────────────────────

  double _time = 0.0;

  /// Called each frame by the owning State — just a field write, no work.
  void setTime(double t) => _time = t;

  // ── Per-song state (pre-normalised to [0, 1]) ─────────────────────────────

  // Fallback: dark navy tones used before the first extraction completes.
  double _c0r = 0.102, _c0g = 0.165, _c0b = 0.290; // dominant
  double _c1r = 0.180, _c1g = 0.314, _c1b = 0.565; // vibrant
  double _c2r = 0.290, _c2g = 0.376, _c2b = 0.502; // muted

  /// Called once per song change — normalises RGB integers to floats once,
  /// so paint() never does any division or conditional logic.
  void setColors(List<Color> colors) {
    final c0 = colors.isNotEmpty ? colors[0] : const Color(0xFF1A2A4A);
    final c1 = colors.length > 1 ? colors[1] : c0;
    final c2 = colors.length > 2 ? colors[2] : c0;

    _c0r = c0.red   / 255.0;  _c0g = c0.green / 255.0;  _c0b = c0.blue / 255.0;
    _c1r = c1.red   / 255.0;  _c1g = c1.green / 255.0;  _c1b = c1.blue / 255.0;
    _c2r = c2.red   / 255.0;  _c2g = c2.green / 255.0;  _c2b = c2.blue / 255.0;
  }

  // ── CustomPainter ─────────────────────────────────────────────────────────

  // Pre-allocated Paint — reused every frame.
  final _paint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    // Bind all 12 uniform floats.
    // Per-frame cost: 12 float writes + 1 drawRect call — negligible Dart work.
    // The heavy work (9 trig calls × 131072 pixels) runs entirely on the GPU.
    shader
      ..setFloat(0,  size.width)   // uSize.x
      ..setFloat(1,  size.height)  // uSize.y
      ..setFloat(2,  _time)        // uTime  ← only this changes per frame
      ..setFloat(3,  _c0r)         // uColor0 (dominant)
      ..setFloat(4,  _c0g)
      ..setFloat(5,  _c0b)
      ..setFloat(6,  _c1r)         // uColor1 (vibrant)
      ..setFloat(7,  _c1g)
      ..setFloat(8,  _c1b)
      ..setFloat(9,  _c2r)         // uColor2 (muted)
      ..setFloat(10, _c2g)
      ..setFloat(11, _c2b);

    _paint.shader = shader;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      _paint,
    );
  }

  @override
  bool shouldRepaint(_ShaderPainter old) => true;
}
