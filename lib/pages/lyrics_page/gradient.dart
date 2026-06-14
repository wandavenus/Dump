part of '../lyrics_page.dart';

class _LyricsGradient extends StatelessWidget {
  const _LyricsGradient();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1A2E), Color(0xFF16213E), Color(0xFF0F3460)],
        ),
      ),
    );
  }
}

// ─── Gradient tepian ───────────────────────────────────────────────────────────
