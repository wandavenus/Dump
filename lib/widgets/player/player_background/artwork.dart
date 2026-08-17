part of '../player_background.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ProceduralFogBackground
//
// Renders the fluid GLSL shader as a living colour-field background.
// Artwork is NEVER drawn — only the palette extracted from it is used.
//
// Performance trick (downscale → upscale):
//   The shader runs on a 256×512 canvas, not the full screen.
//   FittedBox(fit: BoxFit.cover) scales the result to fill any screen size.
//   This reduces GPU pixel work by ~6-8× versus rendering at 1080p while
//   still producing a smooth, blur-like appearance naturally.
//
// Time handling:
//   An AnimationController (30-minute loop) drives the animation.
//   Time is accumulated monotonically via a listener so the shader clock never
//   resets — no visual snap at the loop boundary.
// ─────────────────────────────────────────────────────────────────────────────

class ProceduralFogBackground extends StatefulWidget {
  const ProceduralFogBackground({
    super.key,
    required this.songId,
    required this.palette,
  });

  final int songId;
  final List<Color> palette;

  @override
  State<ProceduralFogBackground> createState() =>
      _ProceduralFogBackgroundState();
}

class _ProceduralFogBackgroundState extends State<ProceduralFogBackground>
    with SingleTickerProviderStateMixin {
  // Render resolution — the shader canvas size before FittedBox upscaling.
  static const double _kW = 256.0;
  static const double _kH = 512.0;

  late final AnimationController _controller;

  // Shader state — null until the async asset load finishes.
  // ignore: unused_field — held to prevent GC from destroying the shader.
  ui.FragmentProgram? _program;
  _ShaderPainter? _painter;

  // Monotonically increasing time (seconds).
  double _t = 0.0;
  double _prev = -1.0;

  @override
  void initState() {
    super.initState();

    // 30-minute loop keeps the visual snap imperceptible; time accumulation
    // in _onTick() prevents any discontinuity at the boundary.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(minutes: 30),
    );
    unawaited(_controller.repeat());

    _controller.addListener(_onTick);
    unawaited(_loadShader());
  }

  // ── Shader loading (once per widget lifetime) ─────────────────────────────

  Future<void> _loadShader() async {
    // F2 fix: a missing/corrupt shader asset or a compile failure on an
    // exotic GPU must never become an unhandled async error. Keeping
    // _painter null is safe — build() already falls back to a dark
    // background while the shader is unavailable.
    ui.FragmentProgram? program;
    try {
      program = await ui.FragmentProgram.fromAsset('assets/shaders/fluid.frag');
    } on Exception catch (e) {
      debugPrint('fluid.frag failed to load: $e');
      return;
    }
    if (!mounted) return;

    final shader = program.fragmentShader();
    final painter = _ShaderPainter(shader: shader, repaint: _controller);
    painter
      ..setTime(_t)
      ..setColors(widget.palette);

    setState(() {
      _program = program; // keep alive — GC would destroy the shader
      _painter = painter;
    });
  }

  // ── Time accumulation ─────────────────────────────────────────────────────

  void _onTick() {
    final v = _controller.value;
    if (_prev >= 0.0) {
      var dt = v - _prev;
      if (dt < 0.0) dt += 1.0; // controller looped (30 min boundary)
      final realDt = dt * 1800.0; // convert to real seconds (1 unit ≈ 1 s)
      // F4 fix: uTime is never sent to the GPU. Every time-dependent shader
      // value (node positions, palette rotation, phases) is computed in Dart
      // (float64) from this unbounded clock and uploaded as uniforms, so GPU
      // float32 precision cannot degrade and no wrap discontinuity is possible
      // even after weeks of uptime.
      _t += realDt;
      _painter?.setTime(_t); // single field write — no state rebuild
      _painter?.advanceBlend(realDt); // advances colour crossfade if active
    }
    _prev = v;
  }

  // ── Widget updates ────────────────────────────────────────────────────────

  @override
  void didUpdateWidget(ProceduralFogBackground old) {
    super.didUpdateWidget(old);
    if (old.palette != widget.palette) {
      _painter?.setColors(widget.palette);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTick);
    _controller.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final painter = _painter;

    // While the shader asset is loading (typically < 1 frame on warm cache,
    // a few frames on first run) show a solid dark background.
    if (painter == null) {
      return const SizedBox.shrink();
    }

    // SizedBox.expand forces FittedBox to receive tight constraints equal to
    // the full available size, so BoxFit.cover scales the 256×512 shader
    // canvas to fill the entire screen regardless of aspect ratio.
    // RepaintBoundary isolates the CustomPaint subtree so only the background
    // repaints on each animation tick — not the entire player UI.
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: RepaintBoundary(
          child: SizedBox(
            width: _kW,
            height: _kH,
            child: CustomPaint(painter: painter),
          ),
        ),
      ),
    );
  }
}
