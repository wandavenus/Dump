part of '../settings_page.dart';

class _GlassSubToggle extends StatelessWidget {
  final String label;
  final ValueNotifier<bool> notifier;
  final Future<void> Function(bool) onChanged;

  const _GlassSubToggle({
    required this.label,
    required this.notifier,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: notifier,
      builder: (_, value, __) => Padding(
        padding: const EdgeInsets.only(left: 36, right: 16, top: 10, bottom: 10),
        child: Row(
          children: [
            const Icon(Icons.blur_on, size: 16, color: Color(0xFF8E8E93)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label,
                  style: const TextStyle(color: Colors.white, fontSize: 15)),
            ),
            CupertinoSwitch(
              value: value,
              onChanged: onChanged,
              activeTrackColor: const Color(0xFFF92D48),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── AUDIO ────────────────────────────────────────────────────────────────────
