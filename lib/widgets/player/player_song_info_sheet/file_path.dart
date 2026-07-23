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
        iconColor: AppColors.of(context).secondaryLabel,
        collapsedIconColor: AppColors.of(context).tertiaryLabel,
        title: Text(
          'File Path',
          style: TextStyle(
            color: AppColors.of(context).primaryLabel,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(
              filePath,
              style: TextStyle(
                color: AppColors.of(context).secondaryLabel,
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
