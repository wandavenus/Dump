part of '../detail_sections.dart';

class _CircleIcon extends StatelessWidget {
  const _CircleIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(150),
        color: const Color.fromARGB(85, 79, 79, 79),
      ),
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Icon(icon, size: 20, color: Colors.red),
      ),
    );
  }
}

// ─── Album hero — pakai SongArtwork dari lagu lokal ────────────────────────
