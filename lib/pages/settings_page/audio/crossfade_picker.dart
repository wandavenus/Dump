part of '../../settings_page.dart';

// ─── Crossfade discrete picker ────────────────────────────────────────────────

class _CrossfadePicker extends StatelessWidget {
  const _CrossfadePicker();

  static const _steps  = [0.0, 1.0, 2.0, 4.0, 6.0, 8.0, 12.0];
  static const _labels = ['Off', '1s', '2s', '4s', '6s', '8s', '12s'];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: AudioEffectsService.crossfadeDuration,
      builder: (_, current, _) {
        // Snap current value to nearest step
        final snapped = _steps.reduce(
          (a, b) => (current - a).abs() <= (current - b).abs() ? a : b,
        );
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Crossfade', style: TextStyle(fontSize: 16)),
              const SizedBox(height: 10),
              CupertinoSlidingSegmentedControl<double>(
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
            ],
          ),
        );
      },
    );
  }
}
