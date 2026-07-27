part of '../player_content.dart';

// ─── Font size picker ─────────────────────────────────────────────────────────

class _FontSizePicker extends StatelessWidget {
  const _FontSizePicker();

  static const List<({String label, double value})> _sizes = [
    (label: 'S', value: 23.0),
    (label: 'M', value: 34.0),
    (label: 'L', value: 48.0),
    (label: 'XL', value: 55.0),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: LyricsSettings.fontSize,
      builder: (_, cur, _) {
        final snapped = _sizes
            .reduce(
              (a, b) => (cur - a.value).abs() <= (cur - b.value).abs() ? a : b,
            )
            .value;
        return SizedBox(
          width: double.infinity,
          child: CupertinoSlidingSegmentedControl<double>(
            groupValue: snapped,
            onValueChanged: (v) {
              if (v != null) LyricsSettings.setFontSize(v);
            },
            children: {
              for (final s in _sizes)
                s.value: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(s.label, style: const TextStyle(fontSize: 13)),
                ),
            },
          ),
        );
      },
    );
  }
}

// ─── Text-align picker ────────────────────────────────────────────────────────

class _AlignPicker extends StatelessWidget {
  const _AlignPicker();

  static const List<({IconData icon, String value})> _opts = [
    (icon: Icons.format_align_left, value: 'left'),
    (icon: Icons.format_align_center, value: 'center'),
    (icon: Icons.format_align_right, value: 'right'),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LyricsSettings.textAlign,
      builder: (_, cur, _) {
        return SizedBox(
          width: double.infinity,
          child: CupertinoSlidingSegmentedControl<String>(
            groupValue: cur,
            onValueChanged: (v) {
              if (v != null) LyricsSettings.setTextAlign(v);
            },
            children: {
              for (final o in _opts)
                o.value: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(o.icon, size: 18),
                ),
            },
          ),
        );
      },
    );
  }
}

// ─── Active-colour picker ─────────────────────────────────────────────────────

class _ColorPicker extends StatelessWidget {
  const _ColorPicker();

  @override
  Widget build(BuildContext context) {
    final opts = [
      (label: context.l10n.lyricsColorWhite, dot: Colors.white, value: 'white'),
      (label: context.l10n.lyricsColorRed, dot: const Color(0xFFF92D48), value: 'accent'),
      (label: context.l10n.lyricsColorYellow, dot: const Color(0xFFFFD60A), value: 'yellow'),
    ];
    return ValueListenableBuilder<String>(
      valueListenable: LyricsSettings.activeColor,
      builder: (_, cur, _) {
        return SizedBox(
          width: double.infinity,
          child: CupertinoSlidingSegmentedControl<String>(
            groupValue: cur,
            onValueChanged: (v) {
              if (v != null) LyricsSettings.setActiveColor(v);
            },
            children: {
              for (final o in opts)
                o.value: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: o.dot,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(o.label, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
            },
          ),
        );
      },
    );
  }
}
