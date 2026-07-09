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
            icon: CupertinoIcons.play_fill,
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
              if (songs.isEmpty) return;
              if (!AudioService.shuffleEnabled) {
                await AudioService.toggleShuffle();
              }
              final randomIndex = Random().nextInt(songs.length);
              await AudioService.playSongAt(playlist: songs, index: randomIndex);
            },
          ),
        ],
      ),
    );
  }
}
