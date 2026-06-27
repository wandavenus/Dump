part of '../settings_page.dart';

class _EqualizerSection extends StatelessWidget {
  const _EqualizerSection();

  static const List<IconData> _presetIcons = [
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader('EQUALIZER'),
        const SizedBox(height: 6),
        ValueListenableBuilder<bool>(
          valueListenable: AudioEffectsService.equalizerEnabled,
          builder: (_, enabled, _) => SettingsToggleRow(
            title: 'Equalizer',
            subtitle: 'Aktifkan preset ruangan',
            value: enabled,
            onChanged: AudioEffectsService.setEqualizerEnabled,
          ),
        ),
        const SettingsDivider(),
        ValueListenableBuilder<int>(
          valueListenable: AudioEffectsService.roomPreset,
          builder: (_, idx, _) => SettingsActionRow(
            title: 'Preset Ruangan',
            trailing: AudioEffectsService.roomPresets[idx]['name'] as String,
            onTap: () => _showPresetPicker(context, idx),
          ),
        ),
        const SettingsDivider(),
      ],
    );
  }

  void _showPresetPicker(BuildContext context, int current) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _RoomPresetSheet(
        current: current,
        icons: _presetIcons,
      ),
    );
  }
}

class _RoomPresetSheet extends StatelessWidget {
  const _RoomPresetSheet({required this.current, required this.icons});
  final int current;
  final List<IconData> icons;

  @override
  Widget build(BuildContext context) {
    const presets = AudioEffectsService.roomPresets;
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Preset Ruangan',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.6,
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: presets.length,
              itemBuilder: (_, i) {
                final selected = i == current;
                final icon = i < icons.length ? icons[i] : Icons.graphic_eq;
                return ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected
                          ? const Color(0xFFF92D48).withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.06),
                    ),
                    child: Icon(
                      icon,
                      size: 18,
                      color: selected
                          ? const Color(0xFFF92D48)
                          : const Color(0xFF8E8E93),
                    ),
                  ),
                  title: Text(
                    presets[i]['name'] as String,
                    style: TextStyle(
                      color: selected
                          ? const Color(0xFFF92D48)
                          : Colors.white,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.normal,
                      fontSize: 15,
                    ),
                  ),
                  subtitle: Text(
                    presets[i]['desc'] as String,
                    style: const TextStyle(
                        color: Color(0xFF636366), fontSize: 12),
                  ),
                  trailing: selected
                      ? const Icon(Icons.check_rounded,
                          color: Color(0xFFF92D48), size: 18)
                      : null,
                  onTap: () {
                    AudioEffectsService.setRoomPreset(i);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ─── SLEEP TIMER ─────────────────────────────────────────────────────────────
