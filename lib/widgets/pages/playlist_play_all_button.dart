import 'package:flutter/material.dart';
import 'package:musicplayer/extensions/localization_extension.dart';

class PlaylistPlayAllButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const PlaylistPlayAllButton({
    super.key,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Text(
            context.l10n.songsCount(count),
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 14),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: colors.onSurface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Icon(Icons.play_arrow, color: colors.surface, size: 18),
                  const SizedBox(width: 4),
                  Text(
                    context.l10n.playAll,
                    style: TextStyle(
                      color: colors.surface,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
