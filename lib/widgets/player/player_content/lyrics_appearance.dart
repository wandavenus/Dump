part of '../player_content.dart';

// ─── Appearance button (circle icon, top-right in lyrics mode) ───────────────

class _AppearanceButton extends StatelessWidget {
  const _AppearanceButton();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _show(context),
      child: Container(
        width: 32,
        height: 32,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color.fromARGB(90, 100, 100, 100),
        ),
        child: const Icon(
          Icons.more_vert_rounded,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }

  void _show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _LyricsAppearanceOverlay(),
    );
  }
}

// ─── Appearance settings sheet ────────────────────────────────────────────────

class _LyricsAppearanceOverlay extends StatelessWidget {
  const _LyricsAppearanceOverlay();

  @override
  Widget build(BuildContext context) {
    // BackdropFilter dihapus — container sudah 0.75 alpha hitam di atas
    // latar gelap full-player, blur di baliknya tidak terlihat secara visual.
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(0)),
      child: ColoredBox(
        color: Colors.black,
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
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                _label('Ukuran Teks'),
                const SizedBox(height: 8),
                const _FontSizePicker(),
                const SizedBox(height: 16),
                _label('Rata Teks'),
                const SizedBox(height: 8),
                const _AlignPicker(),
                const SizedBox(height: 16),
                _label('Warna Aktif'),
                const SizedBox(height: 8),
                const _ColorPicker(),

                const SizedBox(height: 12),
                _ToggleRow(
                  label: 'Highlight Karaoke',
                  subtitle: 'Animasi karakter per karakter',
                  notifier: LyricsSettings.karaokeMode,
                  onChanged: LyricsSettings.setKaraokeMode,
                ),
                const SizedBox(height: 4),
                _ToggleRow(
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

  static Widget _label(String text) => Text(
    text,
    style: const TextStyle(
      color: Color(0xFF8E8E93),
      fontSize: 12,
      fontWeight: FontWeight.w500,
    ),
  );
}

// ─── Reusable toggle row ──────────────────────────────────────────────────────

class _ToggleRow extends StatelessWidget {
  final String label;
  final String? subtitle;
  final ValueNotifier<bool> notifier;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.label,
    this.subtitle,
    required this.notifier,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: notifier,
      builder:
          (_, v, _) => Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 12,
                        ),
                      ),
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
