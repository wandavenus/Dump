part of '../lyrics_page.dart';

class _ColorPicker extends StatelessWidget {
  const _ColorPicker();

  static const _opts = [
    (label: 'Putih',  color: Color(0xFFFFFFFF), value: 'white'),
    (label: 'Merah',  color: Color(0xFFF92D48), value: 'accent'),
    (label: 'Kuning', color: Color(0xFFFFD60A), value: 'yellow'),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LyricsSettings.activeColor,
      builder: (_, cur, _) => Row(
        children: _opts.map((o) {
          final active = cur == o.value;
          return Expanded(
            child: GestureDetector(
              onTap: () => LyricsSettings.setActiveColor(o.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 8),
                height: 40,
                decoration: BoxDecoration(
                  color: active ? o.color : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: active
                      ? null
                      : Border.all(color: o.color.withValues(alpha: 0.4), width: 1),
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
