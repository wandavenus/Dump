part of '../lyrics_page.dart';

class _AlignPicker extends StatelessWidget {
  const _AlignPicker();

  static const _opts = [
    (label: 'Kiri',   icon: Icons.format_align_left,   value: 'left'),
    (label: 'Tengah', icon: Icons.format_align_center, value: 'center'),
    (label: 'Kanan',  icon: Icons.format_align_right,  value: 'right'),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LyricsSettings.textAlign,
      builder: (_, cur, __) => Row(
        children: _opts.map((o) {
          final active = cur == o.value;
          return Expanded(
            child: GestureDetector(
              onTap: () => LyricsSettings.setTextAlign(o.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 8),
                height: 40,
                decoration: BoxDecoration(
                  color: active
                      ? const Color(0xFFF92D48)
                      : Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(o.icon,
                    color: active ? Colors.white : Colors.white54, size: 20),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
