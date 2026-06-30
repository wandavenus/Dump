part of '../player_content.dart';

// ─── Font size picker ─────────────────────────────────────────────────────────

class _FontSizePicker extends StatelessWidget {
  const _FontSizePicker();

  static const _sizes = [
    (label: 'S', value: 23.0),
    (label: 'M', value: 34.0),
    (label: 'L', value: 48.0),
    (label: 'XL', value: 55.0),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: LyricsSettings.fontSize,
      builder:
          (_, cur, _) => Row(
            children:
                _sizes.map((s) {
                  final active = cur == s.value;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => LyricsSettings.setFontSize(s.value),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(right: 8),
                        height: 40,
                        decoration: BoxDecoration(
                          color:
                              active
                                  ? const Color(0xFFF92D48)
                                  : Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          s.label,
                          style: TextStyle(
                            color: active ? Colors.white : Colors.white54,
                            fontWeight:
                                active ? FontWeight.bold : FontWeight.normal,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
          ),
    );
  }
}

// ─── Text-align picker ────────────────────────────────────────────────────────

class _AlignPicker extends StatelessWidget {
  const _AlignPicker();

  static const _opts = [
    (label: 'Kiri', icon: Icons.format_align_left, value: 'left'),
    (label: 'Tengah', icon: Icons.format_align_center, value: 'center'),
    (label: 'Kanan', icon: Icons.format_align_right, value: 'right'),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LyricsSettings.textAlign,
      builder:
          (_, cur, _) => Row(
            children:
                _opts.map((o) {
                  final active = cur == o.value;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => LyricsSettings.setTextAlign(o.value),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(right: 8),
                        height: 40,
                        decoration: BoxDecoration(
                          color:
                              active
                                  ? const Color(0xFFF92D48)
                                  : Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          o.icon,
                          color: active ? Colors.white : Colors.white54,
                          size: 20,
                        ),
                      ),
                    ),
                  );
                }).toList(),
          ),
    );
  }
}

// ─── Active-colour picker ─────────────────────────────────────────────────────

class _ColorPicker extends StatelessWidget {
  const _ColorPicker();

  static const _opts = [
    (label: 'Putih', color: Colors.black, value: 'white'),
    (label: 'Merah', color: Color(0xFFF92D48), value: 'accent'),
    (label: 'Kuning', color: Color(0xFFFFD60A), value: 'yellow'),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LyricsSettings.activeColor,
      builder:
          (_, cur, _) => Row(
            children:
                _opts.map((o) {
                  final active = cur == o.value;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => LyricsSettings.setActiveColor(o.value),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(right: 8),
                        height: 40,
                        decoration: BoxDecoration(
                          color:
                              active
                                  ? o.color
                                  : Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border:
                              active
                                  ? null
                                  : Border.all(
                                    color: o.color.withValues(alpha: 0.4),
                                    width: 1,
                                  ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          o.label,
                          style: TextStyle(
                            color: active ? Colors.white : Colors.white54,
                            fontSize: 13,
                            fontWeight:
                                active ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
          ),
    );
  }
}
