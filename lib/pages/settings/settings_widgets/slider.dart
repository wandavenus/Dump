part of '../settings_widgets.dart';

class SettingsSliderRow extends StatefulWidget {
  final String title;
  final String subtitle;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final Future<void> Function(double) onChanged;

  /// Optional lightweight callback for live previews while dragging. Unlike
  /// [onChanged], this must not perform persistence or other expensive I/O.
  final ValueChanged<double>? onChangedLive;
  final bool showReset;
  final VoidCallback? onReset;

  /// Saat true, slider disembunyikan di balik baris header yang bisa diketuk.
  /// Subtitle tampil sebagai value-hint di header saat collapsed.
  final bool expandable;

  /// Deskripsi singkat yang menjelaskan fungsi fitur ini ke user. Tampil di
  /// bawah slider dengan style redup/italic. Opsional — kalau null, tidak
  /// ada baris tambahan yang dirender.
  final String? description;

  const SettingsSliderRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onChangedLive,
    this.divisions = 20,
    this.showReset = false,
    this.onReset,
    this.expandable = false,
    this.description,
  });

  @override
  State<SettingsSliderRow> createState() => _SettingsSliderRowState();
}

class _SettingsSliderRowState extends State<SettingsSliderRow>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _ctrl;
  late final Animation<double> _fade;

  // Tracks the in-flight drag value so the thumb moves smoothly during a
  // drag gesture. Set on onChanged, cleared on onChangeEnd. The expensive
  // callback (widget.onChanged) is only called once on release — avoids
  // firing async I/O (SharedPreferences, native audio calls) every frame.
  double? _dragValue;

  // Live preview throttling: emit at most one preview every short interval,
  // then coalesce the latest dragged value so the user gets smooth motion
  // without spamming the native layer on every pointer tick.
  Timer? _livePreviewThrottle;
  double? _pendingLivePreviewValue;
  double? _lastLivePreviewValue;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _livePreviewThrottle?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    unawaited(_expanded ? _ctrl.forward() : _ctrl.reverse());
  }

  void _scheduleLivePreview(double value) {
    final callback = widget.onChangedLive;
    if (callback == null) return;

    _pendingLivePreviewValue = value;

    // Emit the first drag update immediately so the slider feels responsive,
    // then coalesce the rest into one update per window.
    if (_livePreviewThrottle == null) {
      _lastLivePreviewValue = value;
      _pendingLivePreviewValue = null;
      callback(value);
      _livePreviewThrottle = Timer(const Duration(milliseconds: 48), () {
        _livePreviewThrottle = null;
        final pending = _pendingLivePreviewValue;
        if (pending == null) return;
        _pendingLivePreviewValue = null;
        if (pending != _lastLivePreviewValue) {
          _lastLivePreviewValue = pending;
          callback(pending);
        }
      });
    }
  }

  Widget _buildSlider(AppThemeExtension c) => SliderTheme(
    data: SliderTheme.of(context).copyWith(
      activeTrackColor: const Color(0xFFF92D48),
      thumbColor: c.primaryLabel,
      inactiveTrackColor: c.separator,
      overlayColor: const Color(0x29F92D48),
      trackHeight: 3,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
    ),
    child: Slider(
      value: (_dragValue ?? widget.value)
          .clamp(widget.min, widget.max)
          .toDouble(),
      min: widget.min,
      max: widget.max,
      divisions: widget.divisions,
      onChanged: (v) {
        setState(() => _dragValue = v);
        _scheduleLivePreview(v);
      },
      onChangeEnd: (v) {
        setState(() => _dragValue = null);
        _livePreviewThrottle?.cancel();
        _livePreviewThrottle = null;
        _pendingLivePreviewValue = null;
        _lastLivePreviewValue = null;
        unawaited(widget.onChanged(v));
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    // ── Non-expandable: layout asli ──────────────────────────────────────────
    if (!widget.expandable) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: TextStyle(color: c.primaryLabel, fontSize: 16),
                  ),
                ),
                if (widget.showReset && widget.onReset != null)
                  GestureDetector(
                    onTap: widget.onReset,
                    child: Text(
                      context.l10n.reset,
                      style: const TextStyle(
                        color: Color(0xFFF92D48),
                        fontSize: 13,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              widget.subtitle,
              style: TextStyle(color: c.secondaryLabel, fontSize: 12),
            ),
            _buildSlider(c),
            if (widget.description != null) ...[
              const SizedBox(height: 2),
              Text(
                widget.description!,
                style: TextStyle(
                  color: c.tertiaryLabel,
                  fontSize: 11,
                  fontStyle: FontStyle.normal,
                  height: 1.3,
                ),
              ),
            ],
          ],
        ),
      );
    }

    // ── Expandable: accordion ────────────────────────────────────────────────
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header — selalu terlihat, bisa diketuk
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(color: c.primaryLabel, fontSize: 16),
                    ),
                  ),
                  Text(
                    widget.subtitle,
                    style: TextStyle(color: c.secondaryLabel, fontSize: 13),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 220),
                    child: const Icon(Icons.expand_more, size: 18),
                  ),
                ],
              ),
            ),
          ),

          // Konten collapsible — fade + naik/turun
          SizeTransition(
            sizeFactor: _ctrl,
            alignment: Alignment.topCenter,
            child: FadeTransition(
              opacity: _fade,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.showReset && widget.onReset != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: widget.onReset,
                        child: Text(
                          context.l10n.reset,
                          style: const TextStyle(
                            color: Color(0xFFF92D48),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  _buildSlider(c),
                  if (widget.description != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        widget.description!,
                        style: TextStyle(
                          color: c.tertiaryLabel,
                          fontSize: 11,
                          fontStyle: FontStyle.normal,
                          height: 1.3,
                        ),
                      ),
                    ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Info Row ─────────────────────────────────────────────────────────────────