part of '../lyrics_page.dart';

class _LyricsAppearanceSheet extends StatelessWidget {
  const _LyricsAppearanceSheet();

  @override
  Widget build(BuildContext context) {
    // BackdropFilter dihapus — container ini sudah 0.75 alpha hitam di atas
    // latar gelap, sehingga blur di baliknya tidak memberikan efek visual.
    // Menggunakan solid color menghemat satu fullscreen blur pass.
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: ColoredBox(
        color: const Color(0xBF0D0D0D),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Tampilan Lirik',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 20),
                  _sheetLabel('Ukuran Teks'),
                  const SizedBox(height: 8),
                  const _FontSizePicker(),
                  const SizedBox(height: 16),
                  _sheetLabel('Rata Teks'),
                  const SizedBox(height: 8),
                  const _AlignPicker(),
                  const SizedBox(height: 16),
                  _sheetLabel('Warna Aktif'),
                  const SizedBox(height: 8),
                  const _ColorPicker(),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Tampilkan Sumber Lirik',
                            style: TextStyle(
                                color: Colors.white, fontSize: 15)),
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: LyricsSettings.showSource,
                        builder: (_, v, _) => CupertinoSwitch(
                          value: v,
                          onChanged: LyricsSettings.setShowSource,
                          activeTrackColor: const Color(0xFFF92D48),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _sheetLabel('Sinkronisasi Waktu'),
                  const SizedBox(height: 10),
                  const _OffsetStepper(),
                ],
              ),
            ),
          ),
        ),
    );
  }

  static Widget _sheetLabel(String text) => Text(
        text,
        style: const TextStyle(
            color: Color(0xFF8E8E93),
            fontSize: 12,
            fontWeight: FontWeight.w500),
      );
}

// ─── Offset stepper ────────────────────────────────────────────────────────────

class _OffsetStepper extends StatelessWidget {
  const _OffsetStepper();

  static const _step = 100; // ms per tap

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: LyricsSettings.lyricsOffset,
      builder: (_, offset, _) {
        final label = offset == 0
            ? '0 ms'
            : '${offset > 0 ? '+' : ''}$offset ms';

        return Row(
          children: [
            // Tombol kurangi (−)
            _StepBtn(
              icon: CupertinoIcons.minus,
              onTap: () => LyricsSettings.setLyricsOffset(offset - _step),
            ),
            const SizedBox(width: 12),
            // Nilai tengah + reset on tap
            Expanded(
              child: GestureDetector(
                onTap: offset != 0
                    ? () => LyricsSettings.setLyricsOffset(0)
                    : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 40,
                  decoration: BoxDecoration(
                    color: offset != 0
                        ? const Color(0xFFF92D48).withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: offset != 0
                          ? const Color(0xFFF92D48).withValues(alpha: 0.4)
                          : Colors.transparent,
                      width: 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: offset != 0
                              ? const Color(0xFFF92D48)
                              : Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (offset != 0) ...[
                        const SizedBox(width: 6),
                        const Icon(CupertinoIcons.xmark_circle_fill,
                            size: 13, color: Color(0xFFF92D48)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Tombol tambah (+)
            _StepBtn(
              icon: CupertinoIcons.plus,
              onTap: () => LyricsSettings.setLyricsOffset(offset + _step),
            ),
          ],
        );
      },
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _StepBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: Colors.white70, size: 18),
      ),
    );
  }
}

// ─── Picker widgets ────────────────────────────────────────────────────────────
