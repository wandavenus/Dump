part of '../settings_page.dart';

// ─── Bit-Perfect Mode Section ───────────────────────────────────────────────
//
// Master switch that force-bypasses every audio-altering feature in the
// app — Equalizer, Bass Boost, Spatial Audio/Virtualizer, Compressor,
// Limiter, Soft Clipper, Crossfeed, ReplayGain, Loudness Normalization,
// Crossfade, Playback Speed, and Pitch Shift — as close to the untouched
// source signal as this device allows. Lives at the top level of Settings,
// not inside the Equalizer page, because it governs the whole app's audio
// path, not just the equalizer.
//
// Turning it back off restores every setting exactly as it was before —
// see [AudioEffectsService.setBitPerfectMode] for the snapshot/restore
// logic.

class _BitPerfectSection extends StatelessWidget {
  const _BitPerfectSection();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AudioEffectsService.bitPerfectMode,
      builder: (context, enabled, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SettingsSectionHeader('BIT-PERFECT'),
            const SizedBox(height: 6),
            SettingsToggleRow(
              title: 'Mode Bit-Perfect',
              subtitle: enabled
                  ? 'Aktif — semua pemrosesan audio dinonaktifkan'
                  : 'Nonaktifkan semua efek & pemrosesan audio',
              value: enabled,
              onChanged: (v) => _confirmAndToggle(context, v),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
              child: Text(
                enabled
                    ?   'Semua fitur DSP dipaksa nonaktif agar sinyal '
                        'sedekat mungkin dengan sumber asli. Kontrol-kontrol '
                        'tersebut dikunci selama mode ini aktif — pengaturan '
                        'sebelumnya akan dikembalikan saat dinonaktifkan.'
                    : 'Saat aktif, semua fitur yang mengubah sinyal audio di '
                        'seluruh aplikasi akan dipaksa Nonaktif.',
                style: const TextStyle(color: Color(0xFF636366), fontSize: 12),
              ),
            ),
            const SettingsDivider(),
          ],
        );
      },
    );
  }

  Future<void> _confirmAndToggle(BuildContext context, bool value) async {
    if (!value) {
      await AudioEffectsService.setBitPerfectMode(false);
      return;
    }
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _BitPerfectConfirmSheet(),
    );
    if (confirmed == true) {
      await AudioEffectsService.setBitPerfectMode(true);
    }
  }
}

class _BitPerfectConfirmSheet extends StatelessWidget {
  const _BitPerfectConfirmSheet();

  @override
  Widget build(BuildContext context) {
    return SwipeToDismissSheet(
      child: Container(
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
                  'Aktifkan Mode Bit-Perfect?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Semua efek dan pemrosesan audio di seluruh aplikasi akan '
                  'dinonaktifkan paksa. Pengaturan '
                  'yang sedang aktif akan disimpan dan dikembalikan otomatis '
                  'saat mode ini dimatikan lagi.',
                  style: TextStyle(color: Color(0xFF8E8E93), fontSize: 13),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoButton(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      color: const Color(0xFF2C2C2E),
                      borderRadius: BorderRadius.circular(12),
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Batal',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CupertinoButton(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      color: const Color(0xFFF92D48),
                      borderRadius: BorderRadius.circular(12),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Aktifkan',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
