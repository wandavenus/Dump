part of '../detail_sections.dart';

class PlayShuffleButtons extends StatelessWidget {
  const PlayShuffleButtons({super.key, required this.songs});

  final List<LocalSong> songs;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          _ActionButton(
            icon: Icons.play_arrow_rounded,
            label: 'Putar',
            onTap: () async {
              await AudioService.playSongAt(playlist: songs, index: 0);
            },
          ),
          const SizedBox(width: 8),
          _ActionButton(
            icon: CupertinoIcons.shuffle,
            label: 'Acak',
            onTap: () async {
              final shuffled = List<LocalSong>.from(songs)..shuffle();
              await AudioService.playSongAt(playlist: shuffled, index: 0);
            },
          ),
        ],
      ),
    );
  }
}
