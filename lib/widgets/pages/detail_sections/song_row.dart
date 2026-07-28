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
    final c = AppColors.of(context);
    return InkWell(
      onTap: () async {
        await AudioService.playSongAt(playlist: playlist, index: index);
      },
      onLongPress: () => showSongContextMenu(
        context,
        song: song,
        playlist: playlist,
        index: index,
      ),
      child: Column(
        children: [
          Divider(
            color: c.subtleSeparator,
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
                    style: TextStyle(fontSize: 14, color: c.secondaryLabel),
                  ),
                ),

                // Title
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          song.title,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            color: c.primaryLabel,
                            fontWeight: FontWeight.w400,
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
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Icon(
                      CupertinoIcons.ellipsis_vertical,
                      size: 20,
                      color: c.secondaryLabel,
                    ),
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
