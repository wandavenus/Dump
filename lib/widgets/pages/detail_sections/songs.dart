part of '../detail_sections.dart';

class SongListSection extends StatelessWidget {
  const SongListSection({
    super.key,
    required this.songs,
    this.showHeader = false,
  });

  final List<LocalSong> songs;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeader)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 20, bottom: 4),
            child: Text(
              context.l10n.topSongs,
              style: TextStyle(
                color: AppColors.of(context).primaryLabel,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ListView.builder(
          padding: const EdgeInsets.only(top: 8),
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: songs.length,
          itemBuilder: (context, index) => SongListRow(
            song: songs[index],
            index: index,
            playlist: songs,
            showDivider: index > 0,
          ),
        ),
      ],
    );
  }
}
