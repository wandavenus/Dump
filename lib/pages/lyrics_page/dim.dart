part of '../lyrics_page.dart';

class _DimSlider extends StatelessWidget {
  const _DimSlider();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: LyricsSettings.bgDim,
      builder: (_, v, _) => Row(
        children: [
          const Icon(Icons.brightness_high, color: Colors.white38, size: 16),
          Expanded(
            child: Slider(
              value: v,
              min: 0.2,
              max: 0.95,
              divisions: 15,
              activeColor: const Color(0xFFF92D48),
              inactiveColor: Colors.white12,
              onChanged: LyricsSettings.setBgDim,
            ),
          ),
          const Icon(Icons.brightness_low, color: Colors.white38, size: 16),
        ],
      ),
    );
  }
}
