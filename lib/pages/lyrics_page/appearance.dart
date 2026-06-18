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
      child: Container(
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
                  _sheetLabel('Kegelapan Latar'),
                  const SizedBox(height: 4),
                  const _DimSlider(),
                  const SizedBox(height: 12),
                  _sheetLabel('Kekuatan Blur'),
                  const SizedBox(height: 4),
                  const _BlurSlider(),
                  const SizedBox(height: 12),
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

// ─── Picker widgets ────────────────────────────────────────────────────────────
