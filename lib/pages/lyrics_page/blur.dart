part of '../lyrics_page.dart';

class _BlurSlider extends StatelessWidget {
  const _BlurSlider();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: LyricsSettings.blurStrength,
      builder: (_, v, __) => Row(
        children: [
          const Icon(CupertinoIcons.photo, color: Colors.white38, size: 16),
          Expanded(
            child: Slider(
              value: v,
              min: 0,
              max: 50,
              divisions: 10,
              activeColor: const Color(0xFFF92D48),
              inactiveColor: Colors.white12,
              onChanged: LyricsSettings.setBlurStrength,
            ),
          ),
          const Icon(Icons.blur_on, color: Colors.white38, size: 16),
        ],
      ),
    );
  }
}
