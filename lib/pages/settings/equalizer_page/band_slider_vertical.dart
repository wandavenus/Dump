part of '../equalizer_page.dart';

// ─── Single vertical band slider ───────────────────────────────────────────────

class _VerticalBandSlider extends StatefulWidget {
  const _VerticalBandSlider({
    required this.gain,
    required this.freqLabel,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onChanged,
    required this.activeTouches,
  });

  final double gain;
  final String freqLabel;
  final double min;
  final double max;
  final bool enabled;
  final ValueChanged<double> onChanged;

  /// Shared counter of active pointers across all band sliders in this
  /// section — incremented on pointer down, decremented on pointer up/cancel.
  final ValueNotifier<int> activeTouches;

  @override
  State<_VerticalBandSlider> createState() => _VerticalBandSliderState();
}

class _VerticalBandSliderState extends State<_VerticalBandSlider>
    with SingleTickerProviderStateMixin {
  /// Pointer ID currently dragging this slider. Null = idle.
  int? _activePointer;

  /// Animation controller for the "pressing" highlight effect.
  late final AnimationController _pressCtrl;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
  }

  // ── Pointer tracking (multitouch-safe via Listener) ───────────────────────

  void _onPointerDown(PointerDownEvent e, BoxConstraints c) {
    if (!widget.enabled || _activePointer != null) return;
    _activePointer = e.pointer;
    widget.activeTouches.value++;
    unawaited(_pressCtrl.forward());
    final v = _yToValue(e.localPosition.dy, c.maxHeight);
    widget.onChanged(v);
  }

  void _onPointerMove(PointerMoveEvent e, BoxConstraints c) {
    if (e.pointer != _activePointer || !widget.enabled) return;
    final v = _yToValue(e.localPosition.dy, c.maxHeight);
    widget.onChanged(v);
  }

  void _onPointerUp(PointerUpEvent e) {
    if (e.pointer != _activePointer) return;
    _activePointer = null;
    widget.activeTouches.value--;
    unawaited(_pressCtrl.reverse());
  }

  void _onPointerCancel(PointerCancelEvent e) {
    if (e.pointer != _activePointer) return;
    _activePointer = null;
    widget.activeTouches.value--;
    unawaited(_pressCtrl.reverse());
  }

  @override
  void dispose() {
    // Safety net: if this slider is disposed mid-drag (e.g. page popped
    // while dragging), make sure its touch is released from the shared
    // counter so the counter never gets stuck above zero.
    if (_activePointer != null) {
      widget.activeTouches.value--;
      _activePointer = null;
    }
    _pressCtrl.dispose();
    super.dispose();
  }

  /// Convert a raw Y coordinate within the track area to a gain value.
  double _yToValue(double y, double trackH) {
    final fraction = 1.0 - (y / trackH).clamp(0.0, 1.0);
    final raw = widget.min + fraction * (widget.max - widget.min);
    // Snap to 0 when within 0.3 dB to make it easy to land on center.
    if (raw.abs() < 0.3) return 0.0;
    return raw.clamp(widget.min, widget.max);
  }

  // ── Label helpers ─────────────────────────────────────────────────────────

  String get _gainLabel {
    final g = widget.gain;
    if (g.abs() < 0.05) return '0';
    return '${g > 0 ? '+' : ''}${g.toStringAsFixed(1)}';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isActive = widget.gain.abs() > 0.1;
    final isDragging = _activePointer != null;
    final c = AppColors.of(context);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // ── dB value label ───────────────────────────────────────────
        SizedBox(
          height: 20,
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 150),
            style: TextStyle(
              color: isDragging || isActive
                  ? Theme.of(context).colorScheme.primary
                  : c.tertiaryLabel,
              fontSize: 10,
              fontWeight: isDragging || isActive
                  ? FontWeight.w600
                  : FontWeight.normal,
            ),
            child: Text(_gainLabel, textAlign: TextAlign.center),
          ),
        ),

        const SizedBox(height: 4),

        // ── Slider track (Listener for multitouch-safe drags) ────────
        Expanded(
          child: LayoutBuilder(
            builder: (_, constraints) => Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (e) => _onPointerDown(e, constraints),
              onPointerMove: (e) => _onPointerMove(e, constraints),
              onPointerUp: _onPointerUp,
              onPointerCancel: _onPointerCancel,
              child: AnimatedBuilder(
                animation: _pressCtrl,
                builder: (_, _) => CustomPaint(
                  size: Size(constraints.maxWidth, constraints.maxHeight),
                  painter: _BandTrackPainter(
                    gain: widget.gain,
                    min: widget.min,
                    max: widget.max,
                    pressAmount: _pressCtrl.value,
                    enabled: widget.enabled,
                    trackBg: c.eqTrackBg,
                    centerTickColor: c.eqCenterTick,
                    disabledAccentColor: c.eqDisabledColor,
                    accentColor: Theme.of(context).colorScheme.primary,
                    neutralTrackColor: c.tertiaryLabel,
                  ),
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 6),

        // ── Frequency label ──────────────────────────────────────────
        SizedBox(
          height: 16,
          child: Text(
            widget.freqLabel,
            style: TextStyle(color: c.secondaryLabel, fontSize: 10),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
