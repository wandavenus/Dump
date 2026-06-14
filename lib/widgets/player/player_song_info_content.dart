part of 'player_song_info_sheet.dart';

class _SongInfoContent extends StatelessWidget {
  final SongInfo songInfo;

  const _SongInfoContent({required this.songInfo});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 26),
          Text(
            songInfo.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            songInfo.artist,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 28),
          _InfoSection(
            title: 'DETAILS',
            children: [
              PlayerSongInfoRow(label: 'Album', value: songInfo.album),
              PlayerSongInfoRow(label: 'Year', value: songInfo.year),
              PlayerSongInfoRow(label: 'Duration', value: songInfo.duration),
            ],
          ),
          const SizedBox(height: 16),
          _InfoSection(
            title: 'AUDIO QUALITY',
            children: [
              PlayerSongInfoRow(label: 'Format', value: songInfo.format),
              PlayerSongInfoRow(label: 'Bitrate', value: songInfo.bitrate),
              PlayerSongInfoRow(
                  label: 'Sample Rate', value: songInfo.sampleRate),
              PlayerSongInfoRow(label: 'File Size', value: songInfo.fileSize),
            ],
          ),
          const SizedBox(height: 16),
          _FilePathSection(filePath: songInfo.filePath),
        ],
      ),
    );
  }
}
