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
  Widget build(BuildContext context) 
    return SwipeToDismissSheet(
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(16),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
    final dragFraction = (_dragOffset / 240).clamp(0.0, 1.0);

    return Transform.translate(
      offset: Offset(0, _dragOffset),
      child: Opacity(
        opacity: 1 - (dragFraction * 0.35),
        child: Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(16),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle + header — swipe down here to dismiss.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: _handleDragUpdate,
                  onVerticalDragEnd: _handleDragEnd,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 12),
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                ),
              ),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Song Info',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Body — constrained to 75% of screen height. Not scrollable
              // internally (fits within the constraint), so the whole card
              // can safely respond to swipe-to-dismiss drags.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.75,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
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
            ],
          ),
        ),
      ),
    );
  }
}
