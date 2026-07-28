part of '../player_song_info_sheet.dart';

class _PlayerSongInfoSheetState extends State<PlayerSongInfoSheet> {
  late final Future<SongInfo> _songInfoFuture;

  /// Live audio format received from native via [PlaybackManager].
  /// Null until the first event arrives or [PlaybackManager.getAudioFormat]
  /// returns a non-null result.
  ///
  /// Data comes from ExoPlayer's onTracksChanged, carrying sampleRate,
  /// channelCount, bitrate, mimeType, codecs, and pcmEncoding from the
  /// actual decoder — not from file metadata.
  Map<String, dynamic>? _liveFormat;
  StreamSubscription<Map<dynamic, dynamic>>? _formatSub;

  @override
  void initState() {
    super.initState();
    _songInfoFuture = SongMetadataService.getSongInfo(widget.song);

    // Subscribe to live audio format changes from the active engine.
    // Fires whenever a new audio track is decoded or the engine changes.
    _formatSub = PlaybackManager.audioFormatStream.listen((event) {
      if (mounted) {
        setState(() => _liveFormat = Map<String, dynamic>.from(event));
      }
    });

    // Also fetch the current format immediately: if the song is already
    // playing when the user opens Song Info, no format-changed event fires
    // while the sheet is open, so we pull a one-shot snapshot to populate
    // the UI right away.
    unawaited(
      PlaybackManager.getAudioFormat().then((fmt) {
        if (mounted && fmt != null && _liveFormat == null) {
          setState(() => _liveFormat = fmt);
        }
      }),
    );
  }

  @override
  void dispose() {
    (_formatSub?.cancel())?.ignore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SwipeToDismissSheet(
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.of(context).surface,
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
                  color: AppColors.of(context).dragHandle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const SizedBox(height: 8),
              // Body — constrained to 75% of screen height. Not scrollable
              // internally (fits within the constraint), so the whole card
              // can safely respond to swipe-to-dismiss drags.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.75,
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
