part of '../detail_sections.dart';

class SongListRow extends StatelessWidget {
  const SongListRow({
    super.key,
    required this.song,
    required this.index,
    required this.playlist,
  });

  final LocalSong song;
  final int index;
  final List<LocalSong> playlist;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        await AudioService.playSongAt(playlist: playlist, index: index);
        PlayerPanelController.instance.open();
      },
      child: Column(
        children: [
          const Divider(
            color: Color.fromARGB(255, 80, 80, 80),
            thickness: .4,
            indent: 58,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  SongArtwork(
                    songId: song.id,
                    size: 50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  Container(
                    width: 280,
                    margin: const EdgeInsets.only(left: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 20),
                        ),
                        Text(
                          song.album,
                          style: const TextStyle(
                            fontSize: 15,
                            color: Colors.grey,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Icon(Icons.more_horiz),
            ],
          ),
        ],
      ),
    );
  }
}
