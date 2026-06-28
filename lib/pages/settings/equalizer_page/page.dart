part of '../equalizer_page.dart';

// ─── EqualizerPage ─────────────────────────────────────────────────────────────
//
// Full-screen halaman Equalizer yang berisi:
//   • Header dengan toggle enable/disable
//   • Preset chips (EQ presets: Flat, Rock, Pop, Jazz, Classical, dll.)
//   • Vertical band EQ sliders — jumlah band dinamis dari native
//   • Reverb section — android.media.audiofx.PresetReverb (7 preset diskrit)
//
// Native Audio Audit (Media3 1.10.1 + Android AudioFx):
// ──────────────────────────────────────────────────────
// ✅ Equalizer      — android.media.audiofx.Equalizer (numberOfBands, bandLevelRange,
//                     getCenterFreq). Semua berjalan langsung di audio session native.
// ✅ PresetReverb   — android.media.audiofx.PresetReverb (7 preset diskrit).
//                     Tidak ada parameter kontinu pada API ini.
// ✗  EQ Presets     — Android Equalizer.numberOfPresets / getPresetName TIDAK digunakan;
//                     preset yang ditampilkan adalah kurva gain custom dari AudioEffectsService.
// ✗  Continuous reverb params — wetLevel, decay, roomSize, dll. TIDAK tersedia
//                     di PresetReverb API. Jangan implementasikan.

class EqualizerPage extends StatelessWidget {
  const EqualizerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EqualizerPageHeader(),
            const Expanded(
              child: SingleChildScrollView(
                physics: BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 8),
                    _EqPresetChips(),
                    _EqBandSliderSection(),
                    _SectionDivider(),
                    _ReverbSection(),
                    SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _EqualizerPageHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 12, 0),
      child: Row(
        children: [
          // Back button
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.of(context).pop(),
            child: const Icon(CupertinoIcons.back, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 4),
          // Title
          const Expanded(
            child: Text(
              'Equalizer',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ),
          // Enable toggle
          ValueListenableBuilder<bool>(
            valueListenable: AudioEffectsService.equalizerEnabled,
            builder: (_, enabled, _) => CupertinoSwitch(
              value: enabled,
              onChanged: AudioEffectsService.setEqualizerEnabled,
              activeTrackColor: const Color(0xFFF92D48),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Reusable section divider ─────────────────────────────────────────────────

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Divider(color: Color(0xFF2C2C2E), height: 1),
    );
  }
}

// ─── Section label ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Row(
        children: [
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF8E8E93),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
          if (trailing != null) ...[
            const Spacer(),
            trailing!,
          ],
        ],
      ),
    );
  }
}
