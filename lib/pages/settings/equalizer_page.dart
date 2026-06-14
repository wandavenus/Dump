import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import '../../services/audio/audio_effects_service.dart';

/// Halaman pemilihan preset ruangan — menggabungkan reverb + EQ
/// dalam satu pilihan yang mudah dipahami.
class EqualizerPage extends StatelessWidget {
  const EqualizerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(context),
            const SizedBox(height: 8),
            _buildEqToggle(),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'PRESET RUANGAN',
                  style: TextStyle(
                    color: Color(0xFF8E8E93),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(child: _RoomPresetGrid()),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.of(context).pop(),
            child: const Icon(CupertinoIcons.back, color: Colors.white),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Preset Ruangan',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEqToggle() {
    return ValueListenableBuilder<bool>(
      valueListenable: AudioEffectsService.equalizerEnabled,
      builder: (_, enabled, __) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.equalizer, color: Color(0xFFF92D48), size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Equalizer',
                      style: TextStyle(color: Colors.white, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      enabled
                          ? 'Preset ruangan aktif'
                          : 'Nonaktif — audio diputar flat',
                      style: const TextStyle(
                          color: Color(0xFF8E8E93), fontSize: 12),
                    ),
                  ],
                ),
              ),
              CupertinoSwitch(
                value: enabled,
                onChanged: AudioEffectsService.setEqualizerEnabled,
                activeColor: const Color(0xFFF92D48),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Room preset grid ─────────────────────────────────────────────────────────

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
      builder: (_, selected, __) {
        return ValueListenableBuilder<bool>(
          valueListenable: AudioEffectsService.equalizerEnabled,
          builder: (_, enabled, __) {
            final presets = AudioEffectsService.roomPresets;
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
                          ? const Color(0xFFF92D48).withOpacity(0.15)
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
