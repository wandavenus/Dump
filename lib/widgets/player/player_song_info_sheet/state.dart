part of '../player_song_info_sheet.dart';

class _PlayerSongInfoSheetState extends State<PlayerSongInfoSheet> {
  late final Future<SongInfo> _songInfoFuture;

  /// Live audio format received from the active engine via [AudioEngineManager].
  /// Null until the first event arrives or [AudioEngineManager.getAudioFormat]
  /// returns a non-null result.
  ///
  /// On Media3Engine: data comes from ExoPlayer's onTracksChanged, carrying
  /// sampleRate, channelCount, bitrate, mimeType, codecs, pcmEncoding from
  /// the actual decoder — not from file metadata.
  ///
  /// On MediaKitEngine: this will remain null (media_kit does not expose
  /// decoder-level audio format info).
  Map<String, dynamic>? _liveFormat;
  StreamSubscription<Map<dynamic, dynamic>>? _formatSub;

  @override
  void initState() {
    super.initState();
    _songInfoFuture = SongMetadataService.getSongInfo(widget.song);

    // Subscribe to live audio format changes from the active engine.
    // Fires whenever a new audio track is decoded or the engine changes.
    _formatSub = AudioEngineManager.audioFormatStream.listen((event) {
      if (mounted) {
        setState(() => _liveFormat = Map<String, dynamic>.from(event));
      }
    });

    // Also fetch the current format immediately: if the song is already
    // playing when the user opens Song Info, no format-changed event fires
    // while the sheet is open, so we pull a one-shot snapshot to populate
    // the UI right away.
    AudioEngineManager.getAudioFormat().then((fmt) {
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
