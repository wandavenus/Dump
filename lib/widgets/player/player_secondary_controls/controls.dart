part of '../player_secondary_controls.dart';

class PlayerSecondaryControls extends StatelessWidget {
  final LocalSong song;
  final bool showLyrics;
  final VoidCallback onLyricsToggle;
  final bool showQueue;
  final VoidCallback onQueueToggle;

  const PlayerSecondaryControls({
    super.key,
    required this.song,
    required this.showLyrics,
    required this.onLyricsToggle,
    required this.showQueue,
    required this.onQueueToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _LyricsToggleButton(active: showLyrics, onTap: onLyricsToggle),
          const SizedBox(width: 140),
          _QueueToggleButton(active: showQueue, onTap: onQueueToggle),
        ],
      ),
    );
  }
}

// ─── Lyrics toggle button ─────────────────────────────────────────────────────

class _LyricsToggleButton extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;

  const _LyricsToggleButton({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color:
              active
                  ? Colors.white.withValues(alpha: 0.15)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          CupertinoIcons.quote_bubble,
          size: 24,
          color: active ? const Color(0xFFF92D48) : Colors.white,
        ),
      ),
    );
  }
}

// ─── Queue toggle button ──────────────────────────────────────────────────────

class _QueueToggleButton extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;

  const _QueueToggleButton({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color:
              active
                  ? Colors.white.withValues(alpha: 0.15)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          CupertinoIcons.list_bullet,
          size: 24,
          color: active ? const Color(0xFFF92D48) : Colors.white,
        ),
      ),
    );
  }
}
