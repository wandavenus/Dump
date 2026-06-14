part of '../detail_sections.dart';

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
