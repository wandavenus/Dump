import 'package:flutter/material.dart';

class PlaylistEmptyState extends StatelessWidget {
  const PlaylistEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: Text(
        'Belum ada lagu',
        style: TextStyle(
          color: colors.onSurfaceVariant,
          fontSize: 16,
        ),
      ),
    );
  }
}
