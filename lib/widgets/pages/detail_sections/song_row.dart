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
      onLongPress: () => showSongContextMenu(
        context,
        song: song,
        playlist: playlist,
        index: index,
      ),
      child: Column(
        children: [
          const Divider(
            color: Color(0xFF38383A),
            thickness: 0.4,
            height: 1,
            indent: 44,
            endIndent: 0,
          ),
          SizedBox(
            height: 50,
            child: Row(
              children: [
                // Track number
                SizedBox(
                  width: 44,
                  child: Text(
                    '${index + 1}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF8E8E93),
                    ),
                  ),
                ),

                // Title + explicit badge
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          song.title,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            color: Colors.white,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFF636366),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Text(
                          'E',
                          style: TextStyle(
                            fontSize: 8,
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Three-dot menu
                GestureDetector(
                  onTap: () => showSongContextMenu(
                    context,
                    song: song,
                    playlist: playlist,
                    index: index,
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Icon(Icons.more_vert, size: 20, color: Color(0xFF8E8E93)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
