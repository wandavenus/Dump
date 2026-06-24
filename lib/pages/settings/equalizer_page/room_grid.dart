part of '../equalizer_page.dart';

class _RoomPresetGrid extends StatelessWidget {
  const _RoomPresetGrid();

  static const List<IconData> _icons = [
    Icons.radio_button_unchecked,
    Icons.mic,
    Icons.theater_comedy,
    Icons.music_note,
    Icons.church,
    Icons.nightlife,
    Icons.park,
    Icons.directions_car,
    Icons.bathroom,
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AudioEffectsService.roomPreset,
      builder: (_, selected, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: AudioEffectsService.equalizerEnabled,
          builder: (_, enabled, _) {
            const presets = AudioEffectsService.roomPresets;
            return GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.9,
              ),
              itemCount: presets.length,
              itemBuilder: (context, i) {
                final preset = presets[i];
                final isSelected = i == selected;
                final icon = i < _icons.length
                    ? _icons[i]
                    : Icons.graphic_eq;

                return GestureDetector(
                  onTap: () => AudioEffectsService.setRoomPreset(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFF92D48).withValues(alpha: 0.15)
                          : const Color(0xFF1C1C1E),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFFF92D48)
                            : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          icon,
                          size: 28,
                          color: isSelected
                              ? const Color(0xFFF92D48)
                              : const Color(0xFF8E8E93),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          preset['name'] as String,
                          style: TextStyle(
                            color: isSelected ? Colors.white : const Color(0xFFAEAEB2),
                            fontSize: 13,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            preset['desc'] as String,
                            style: const TextStyle(
                              color: Color(0xFF636366),
                              fontSize: 10,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
