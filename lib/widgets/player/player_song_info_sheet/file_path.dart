part of '../player_song_info_sheet.dart';

class _FilePathSection extends StatelessWidget {
  final String filePath;

  const _FilePathSection({required this.filePath});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 18),
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        iconColor: Colors.white70,
        collapsedIconColor: Colors.white54,
        title: const Text(
          'File Path',
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(
              filePath,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
