part of '../lyrics_page.dart';

class _LyricsAppearanceSheet extends StatelessWidget {
  const _LyricsAppearanceSheet();

  @override
  Widget build(BuildContext context) {
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
                _SwitchRow(
                  label: 'Highlight Karaoke',
                  subtitle: 'Animasi karakter per karakter',
                  notifier: LyricsSettings.karaokeMode,
                  onChanged: LyricsSettings.setKaraokeMode,
                ),
                const SizedBox(height: 4),
                _SwitchRow(
                  label: 'Tampilkan Sumber Lirik',
                  notifier: LyricsSettings.showSource,
                  onChanged: LyricsSettings.setShowSource,
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

// ─── Reusable toggle row ───────────────────────────────────────────────────────

class _SwitchRow extends StatelessWidget {
  final String label;
  final String? subtitle;
  final ValueNotifier<bool> notifier;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.label,
    this.subtitle,
    required this.notifier,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: notifier,
      builder: (_, v, _) => Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 15)),
                if (subtitle != null) ...[
                  const SizedBox(height: 1),
                  Text(subtitle!,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 12)),
                ],
              ],
            ),
          ),
          CupertinoSwitch(
            value: v,
            onChanged: onChanged,
            activeTrackColor: const Color(0xFFF92D48),
          ),
        ],
      ),
    );
  }
}

// ─── Picker widgets ────────────────────────────────────────────────────────────
