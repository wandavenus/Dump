import 'package:flutter/material.dart';

class PlayerEmptyState extends StatelessWidget {
  const PlayerEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.music_note, size: 64, color: Colors.white38),
          const SizedBox(height: 16),
          const Text(
            'No song selected',
            style: TextStyle(color: Colors.white70, fontSize: 18),
          ),
          const SizedBox(height: 24),
          TextButton(
            onPressed: () => Navigator.maybePop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
