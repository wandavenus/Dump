part of '../equalizer_page.dart';

// ─── Reverb Section ────────────────────────────────────────────────────────────
//
// AUDIT android.media.audiofx.PresetReverb (digunakan oleh AudioEffectsManager.kt)
// ─────────────────────────────────────────────────────────────────────────────────
//
// API yang BENAR-BENAR tersedia:
//   ✅ preset (short)     — set via PresetReverb.preset = SHORT_PRESET_CONSTANT
//   ✅ 7 preset diskrit:
//        PRESET_NONE       = 0
//        PRESET_SMALLROOM  = 1
//        PRESET_MEDIUMROOM = 2
//        PRESET_LARGEROOM  = 3
//        PRESET_MEDIUMHALL = 4
//        PRESET_LARGEHALL  = 5
//        PRESET_PLATE      = 6
//
// Parameter yang TIDAK ADA di API ini (jangan diimplementasi):
//   ✗  wetLevel   — PresetReverb tidak mengekspos kontrol wet/dry
//   ✗  roomSize   — tidak ada parameter kontinu
//   ✗  decayTime  — tidak ada parameter kontinu
//   ✗  damping    — tidak ada parameter kontinu
//   ✗  predelay   — tidak ada parameter kontinu
//   ✗  diffusion  — tidak ada parameter kontinu
//
// Media3 1.10.1 tidak memiliki reverb API sendiri. Kita menggunakan
// android.media.audiofx.PresetReverb langsung pada audio session ID
// yang dikelola oleh Media3PlaybackService.kt.
//
// Ketersediaan tergantung hardware. Beberapa perangkat MIUI/Xiaomi tidak
// mengekspos EFFECT_TYPE_PRESET_REVERB — `AudioEngine.reverbSupported`
// akan false pada perangkat tersebut.

class _ReverbSection extends StatelessWidget {
  const _ReverbSection();

  // Icons untuk setiap PresetReverb preset (index 0–6)
  static const List<IconData> _presetIcons = [
    Icons.music_off_outlined,         // 0  None
    Icons.meeting_room_outlined,      // 1  Small Room
    Icons.home_outlined,              // 2  Medium Room
    Icons.warehouse_outlined,         // 3  Large Room
    Icons.domain_outlined,            // 4  Medium Hall
    Icons.location_city_outlined,     // 5  Large Hall
    Icons.album_outlined,             // 6  Plate
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('REVERB'),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Text(
            // Jujurkan batasan native API kepada pengguna.
            'android.media.audiofx.PresetReverb — 7 preset diskrit. '
            'Tidak ada parameter kontinu (wet/dry, decay, roomSize, dll.) pada API ini.',
            style: TextStyle(color: Color(0xFF636366), fontSize: 11, height: 1.4),
          ),
        ),
        const SizedBox(height: 14),
        AudioEngine.reverbSupported
            ? _buildPresetGrid()
            : _buildUnsupportedMessage(),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildUnsupportedMessage() {
    // Ditampilkan jika AudioEffectsManager.reverbSupported = false.
    // Penyebab umum: AudioEffect.EFFECT_TYPE_PRESET_REVERB tidak tersedia
    // di perangkat ini (beberapa ROM MIUI/Xiaomi).
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded,
                color: Color(0xFF636366), size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'PresetReverb tidak tersedia di perangkat ini.\n'
                'AudioEffect.EFFECT_TYPE_PRESET_REVERB tidak didukung '
                'atau diblokir oleh ROM.',
                style: TextStyle(
                    color: Color(0xFF636366), fontSize: 12, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetGrid() {
    const names = AudioEffectsService.reverbPresetNames;

    return ValueListenableBuilder<int>(
      valueListenable: AudioEffectsService.reverbPreset,
      builder: (_, selected, _) {
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 0.95,
          ),
          itemCount: names.length,
          itemBuilder: (_, i) => _ReverbPresetTile(
            index: i,
            name: names[i],
            icon: i < _presetIcons.length ? _presetIcons[i] : Icons.graphic_eq,
            isSelected: i == selected,
          ),
        );
      },
    );
  }
}

// ─── Single reverb tile ───────────────────────────────────────────────────────

class _ReverbPresetTile extends StatelessWidget {
  const _ReverbPresetTile({
    required this.index,
    required this.name,
    required this.icon,
    required this.isSelected,
  });

  final int index;
  final String name;
  final IconData icon;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => AudioEffectsService.setReverb(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFF92D48).withValues(alpha: 0.14)
              : const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFF92D48)
                : Colors.white.withValues(alpha: 0.06),
            width: 1.4,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 24,
              color: isSelected
                  ? const Color(0xFFF92D48)
                  : const Color(0xFF8E8E93),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                name,
                style: TextStyle(
                  color: isSelected ? Colors.white : const Color(0xFFAEAEB2),
                  fontSize: 10,
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.normal,
                  height: 1.2,
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
  }
}
