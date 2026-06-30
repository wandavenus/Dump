part of '../equalizer_page.dart';

// ─── EQ Preset Chips ──────────────────────────────────────────────────────────
//
// Menampilkan preset EQ sebagai chip horizontal yang bisa di-scroll.
// Preset didefinisikan di AudioEffectsService.eqPresets (Flat, Classical,
// Dance, Folk, Heavy Metal, Hip-Hop, Jazz, Pop, Rock, dll.)
//
// Audit native: Android Equalizer memiliki getNumberOfPresets()/getPresetName()
// tetapi variasi antar device sangat besar dan tidak reliable. Project ini
// menggunakan kurva gain custom (AudioEffectsService.eqPresets) yang dikirim
// ke native via setBandLevel() — lebih konsisten lintas device.

class _EqPresetChips extends StatelessWidget {
  const _EqPresetChips();

  @override
  Widget build(BuildContext context) {
    const presets = AudioEffectsService.eqPresets;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('PRESET'),
        const SizedBox(height: 10),
        SizedBox(
          height: 36,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            physics: const ClampingScrollPhysics(),
            itemCount: presets.length,
            itemBuilder: (_, i) {
              return Padding(
                padding: EdgeInsets.only(right: i < presets.length - 1 ? 8 : 0),
                child: _PresetChip(index: i),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final name = AudioEffectsService.eqPresets[index]['name'] as String;

    return ValueListenableBuilder<bool>(
      valueListenable: AudioEffectsService.equalizerEnabled,
      builder: (_, enabled, _) {
        return ValueListenableBuilder<int>(
          valueListenable: AudioEffectsService.eqPreset,
          builder: (_, currentPreset, _) {
            final isSelected = currentPreset == index;

            return GestureDetector(
              onTap:
                  enabled
                      ? () => AudioEffectsService.applyEqPreset(index)
                      : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 0,
                ),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color:
                      isSelected
                          ? const Color(0xFFF92D48)
                          : enabled
                          ? Colors.white.withValues(alpha: 0.09)
                          : Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color:
                        isSelected
                            ? const Color(0xFFF92D48)
                            : enabled
                            ? Colors.white.withValues(alpha: 0.12)
                            : Colors.white.withValues(alpha: 0.05),
                    width: 1.0,
                  ),
                ),
                child: Text(
                  name,
                  style: TextStyle(
                    color:
                        isSelected
                            ? Colors.white
                            : enabled
                            ? Colors.white.withValues(alpha: 0.85)
                            : Colors.white.withValues(alpha: 0.35),
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
