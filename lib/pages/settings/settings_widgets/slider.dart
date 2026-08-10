part of '../settings_widgets.dart';

class SettingsSliderRow extends StatefulWidget {
  final String title;
  final String subtitle;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final Future<void> Function(double) onChanged;
  final ValueChanged<double>? onChangedLive;
  final bool showReset;
  final VoidCallback? onReset;
  final bool expandable;
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
  double? _dragValue;

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
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    unawaited(_expanded ? _ctrl.forward() : _ctrl.reverse());
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
      divisions: widget.onChangedLive == null ? widget.divisions : null,
      onChanged: (v) {
        setState(() => _dragValue = v);
        widget.onChangedLive?.call(v);
      },
      onChangeEnd: (v) {
        setState(() => _dragValue = null);
        unawaited(widget.onChanged(v));
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      widget.title,
                      style: TextStyle(color: c.primaryLabel, fontSize: 16),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      widget.subtitle,
                      style: TextStyle(color: c.secondaryLabel, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
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
