import 'package:flutter/material.dart';

import '../../models/local_song.dart';
import '../../models/song_info.dart';
import '../../services/song_metadata_service.dart';
import 'player_song_info_row.dart';

class PlayerSongInfoSheet extends StatefulWidget {
  final LocalSong song;

  const PlayerSongInfoSheet({super.key, required this.song});

  @override
  State<PlayerSongInfoSheet> createState() => _PlayerSongInfoSheetState();
}

class _PlayerSongInfoSheetState extends State<PlayerSongInfoSheet> {
  late final Future<SongInfo> _songInfoFuture;

  @override
  void initState() {
    super.initState();
    _songInfoFuture = SongMetadataService.getSongInfo(widget.song);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2A2A2E), Color(0xFF121214)],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: FutureBuilder<SongInfo>(
              future: _songInfoFuture,
              builder: (context, snapshot) {
                final songInfo = snapshot.data;

                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: songInfo == null
                      ? const _LoadingSongInfo()
                      : _SongInfoContent(songInfo: songInfo),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingSongInfo extends StatelessWidget {
  const _LoadingSongInfo();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 360,
      child: Center(
        child: CircularProgressIndicator(color: Color(0xFFF92D48)),
      ),
    );
  }
}

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
              PlayerSongInfoRow(label: 'Sample Rate', value: songInfo.sampleRate),
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

class _InfoSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _InfoSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFF92D48),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }
}

class _FilePathSection extends StatelessWidget {
  final String filePath;

  const _FilePathSection({required this.filePath});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
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
      ),
    );
  }
}
