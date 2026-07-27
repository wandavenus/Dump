import 'package:flutter/material.dart';
import 'package:musicplayer/extensions/localization_extension.dart';

class PlaylistEmptyState extends StatelessWidget {
  const PlaylistEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: Text(
        context.l10n.noSongsYet,
        style: TextStyle(
          color: colors.onSurfaceVariant,
          fontSize: 16,
        ),
      ),
    );
  }
}
