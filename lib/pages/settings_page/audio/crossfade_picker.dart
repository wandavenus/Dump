part of '../../settings_page.dart';

// ─── Crossfade discrete picker ────────────────────────────────────────────────

class _CrossfadePicker extends StatefulWidget {
  const _CrossfadePicker();

  @override
  State<_CrossfadePicker> createState() => _CrossfadePickerState();
}

class _CrossfadePickerState extends State<_CrossfadePicker>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _ctrl;
  late final Animation<double>   _fade;

  static const _steps  = [0.0, 1.0, 2.0, 4.0, 6.0, 8.0, 12.0];
  static const _labels = ['Off', '1s', '2s', '4s', '6s', '8s', '12s'];

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
    _expanded ? _ctrl.forward() : _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ValueListenableBuilder<double>(
      valueListenable: AudioEffectsService.crossfadeDuration,
      builder: (_, current, _) {
        final snapped = _steps.reduce(
          (a, b) => (current - a).abs() <= (current - b).abs() ? a : b,
        );
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              InkWell(
                onTap:        _toggle,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  child: Row(
                    children: [
                      Text('Crossfade',
                          style: TextStyle(color: c.primaryLabel, fontSize: 16)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          current == 0
                              ? 'Nonaktif'
                              : '${current.toStringAsFixed(0)} detik',
                          style: TextStyle(
                              color: c.secondaryLabel, fontSize: 13),
                        ),
                      ),
                      AnimatedRotation(
                        turns:    _expanded ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 220),
                        child: Icon(Icons.keyboard_arrow_down,
                            color: c.primaryLabel.withValues(alpha: 0.38), size: 18),
                      ),
                    ],
                  ),
                ),
              ),
              // Collapsible segmented control
              SizeTransition(
                sizeFactor: _ctrl,
                alignment:  Alignment.topCenter,
                child: FadeTransition(
                  opacity: _fade,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: CupertinoSlidingSegmentedControl<double>(
                      groupValue: snapped,
                      onValueChanged: (v) {
                        if (v != null) AudioEffectsService.setCrossfade(v);
                      },
                      children: {
                        for (var i = 0; i < _steps.length; i++)
                          _steps[i]: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              _labels[i],
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
