part of '../settings_widgets.dart';

// ─── Bit-Perfect Mode lock wrapper ──────────────────────────────────────────
//
// Wraps any settings section that alters the audio signal (Equalizer,
// ReplayGain, Loudness Normalization, Crossfeed, Crossfade,
// Compressor, Limiter, Soft Clipper, Bass Boost, Speed, Pitch). While
// [AudioEffectsService.bitPerfectMode] is on, the wrapped controls are
// visually dimmed and unresponsive to touch — this keeps the UI honest:
// Bit-Perfect Mode really does own every audio-altering control while
// active, instead of silently letting another toggle drift the signal path
// out from under it.

class BitPerfectLock extends StatelessWidget {
  const BitPerfectLock({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AudioEffectsService.bitPerfectMode,
      builder: (_, locked, _) {
        if (!locked) return child;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _BitPerfectLockBanner(),
            IgnorePointer(
              child: Opacity(opacity: 0.35, child: child),
            ),
          ],
        );
      },
    );
  }
}

class _BitPerfectLockBanner extends StatelessWidget {
  const _BitPerfectLockBanner();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          Icon(Icons.lock_outline_rounded, size: 14, color: Color(0xFFF92D48)),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              'Dikunci nonaktif — Mode Bit-Perfect sedang aktif',
              style: TextStyle(color: Color(0xFFF92D48), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
