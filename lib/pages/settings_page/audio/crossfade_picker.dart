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
    return ValueListenableBuilder<double>(
      valueListenable: AudioEffectsService.crossfadeDuration,
      builder: (_, current, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              InkWell(
                onTap:         _toggle,
                borderRadius:  BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  child: Row(
                    children: [
                      const Text('Crossfade',
                          style: TextStyle(color: Colors.white, fontSize: 16)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          current == 0
                              ? 'Nonaktif'
                              : '${current.toStringAsFixed(0)} detik',
                          style: const TextStyle(
                              color: Color(0xFF8E8E93), fontSize: 13),
                        ),
                      ),
                      AnimatedRotation(
                        turns:    _expanded ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 220),
                        child: const Icon(Icons.keyboard_arrow_down,
                            color: Colors.white38, size: 18),
                      ),
                    ],
                  ),
                ),
              ),
              // Collapsible duration buttons
              SizeTransition(
                sizeFactor: _ctrl,
                alignment:  Alignment.topCenter,
                child: FadeTransition(
                  opacity: _fade,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: List.generate(_steps.length, (i) {
                        final active = current == _steps[i];
                        final isLast = i == _steps.length - 1;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () =>
                                AudioEffectsService.setCrossfade(_steps[i]),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: isLast
                                  ? EdgeInsets.zero
                                  : const EdgeInsets.only(right: 5),
                              height: 36,
                              decoration: BoxDecoration(
                                color: active
                                    ? const Color(0xFFF92D48)
                                    : Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                _labels[i],
                                style: TextStyle(
                                  color: active
                                      ? Colors.white
                                      : Colors.white54,
                                  fontWeight: active
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
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
