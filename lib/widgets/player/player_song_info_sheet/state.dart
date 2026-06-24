part of '../player_song_info_sheet.dart';

class _PlayerSongInfoSheetState extends State<PlayerSongInfoSheet> {
  late final Future<SongInfo> _songInfoFuture;

  /// Live audio format received from ExoPlayer via the audioFormat EventChannel.
  /// Null until the first event arrives or [Media3PlaybackBridge.getAudioFormat]
  /// returns a non-null result.
  Map<String, dynamic>? _liveFormat;
  StreamSubscription<Map<dynamic, dynamic>>? _formatSub;

  @override
  void initState() {
    super.initState();
    _songInfoFuture = SongMetadataService.getSongInfo(widget.song);

    // Subscribe to live audio format from ExoPlayer's onTracksChanged.
    // The event fires whenever a new audio track is decoded, carrying
    // sampleRate, channelCount, bitrate, mimeType, codecs, pcmEncoding
    // from the actual Media3 decoder — not from file metadata.
    _formatSub = Media3PlaybackBridge.audioFormatStream.listen((event) {
      if (mounted) {
        setState(() => _liveFormat = Map<String, dynamic>.from(event));
      }
    });

    // Also fetch the current format immediately: if the song is already
    // playing when the user opens Song Info, no onTracksChanged fires while
    // the sheet is open, so we pull a one-shot snapshot to populate the UI.
    Media3PlaybackBridge.getAudioFormat().then((fmt) {
      if (mounted && fmt != null && _liveFormat == null) {
        setState(() => _liveFormat = fmt);
      }
    });
  }

  @override
  void dispose() {
    _formatSub?.cancel();
    super.dispose();
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
                      : _SongInfoContent(
                          songInfo: songInfo,
                          liveFormat: _liveFormat,
                        ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
