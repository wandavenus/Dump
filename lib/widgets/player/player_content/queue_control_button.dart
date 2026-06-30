part of '../player_content.dart';

// ─── Queue control button (shuffle / loop / autoplay) ─────────────────────────

class _QueueControlButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _QueueControlButton({
    required this.icon,
    required this.active,
    required this.onTap,
  });

  static const _activeColor = Color(0xFF8E8E93);
  static const _inactiveColor = Colors.white;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        height: 36,
        decoration: BoxDecoration(
          color:
              active
                  ? _activeColor.withValues(alpha: 0.48)
                  : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Icon(
            icon,
            size: 20,
            color: active ? _activeColor : _inactiveColor,
          ),
        ),
      ),
    );
  }
}
