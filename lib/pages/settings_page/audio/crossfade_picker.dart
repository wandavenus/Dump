part of '../../settings_page.dart';

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

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
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
              InkWell(
                onTap:        _toggle,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  child: Row(
                    children: [
                      Text(l.crossfadeTitle,
                          style: TextStyle(color: c.primaryLabel, fontSize: 16)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          current == 0
                              ? l.off
                              : l.crossfadeSeconds(current.toStringAsFixed(0)),
                          style: TextStyle(color: c.secondaryLabel, fontSize: 13),
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
                        if (v != null) unawaited(AudioEffectsService.setCrossfade(v));
                      },
                      children: {
                        for (var i = 0; i < _steps.length; i++)
                          _steps[i]: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                               i == 0
                                   ? context.l10n.crossfadeOptionOff
                                   : context.l10n.crossfadeOptionSeconds(
                                       _steps[i].toStringAsFixed(0)),
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
