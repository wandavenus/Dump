part of 'player_song_info_sheet.dart';

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
