part of 'detail_sections.dart';

// ─── Tombol play/shuffle ───────────────────────────────────────────────────

class PlayShuffleButtons extends StatelessWidget {
  const PlayShuffleButtons({super.key, required this.songs});

  final List<LocalSong> songs;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ActionButton(
            icon: Icons.play_arrow_rounded,
            label: 'Play',
            onTap: () async {
              await AudioService.playSongAt(playlist: songs, index: 0);
              PlayerPanelController.instance.open();
            },
          ),
          _ActionButton(
            icon: Icons.shuffle_rounded,
            label: 'Shuffle',
            onTap: () async {
              final shuffled = List<LocalSong>.from(songs)..shuffle();
              await AudioService.playSongAt(playlist: shuffled, index: 0);
              PlayerPanelController.instance.open();
            },
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton(
      {required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 50,
        width: 160,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: const Color.fromARGB(85, 79, 79, 79),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.red, size: 30),
            Text(
              label,
              style: const TextStyle(
                color: Colors.red,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
