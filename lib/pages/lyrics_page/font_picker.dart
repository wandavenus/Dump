part of '../lyrics_page.dart';

class _FontSizePicker extends StatelessWidget {
  const _FontSizePicker();

  static const _sizes = [
    (label: 'S', value: 14.0),
    (label: 'M', value: 18.0),
    (label: 'L', value: 22.0),
    (label: 'XL', value: 26.0),
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
