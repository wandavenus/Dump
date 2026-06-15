part of '../lyrics_page.dart';

class _LyricsHeader extends StatelessWidget {
  final LocalSong song;
  const _LyricsHeader({required this.song});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Padding(
      padding: EdgeInsets.only(top: top + 8, left: 16, right: 16, bottom: 8),
      child: Row(
        children: [
          _CircleButton(
            icon: CupertinoIcons.chevron_down,
            onTap: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600),
                ),
                Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
                ),
              ],
            ),
          ),
          _CircleButton(
            icon: CupertinoIcons.textformat,
            onTap: () => _showAppearanceSettings(context),
          ),
        ],
      ),
    );
  }

  void _showAppearanceSettings(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _LyricsAppearanceSheet(),
    );
  }
}
