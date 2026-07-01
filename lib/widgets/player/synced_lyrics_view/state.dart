part of '../synced_lyrics_view.dart';

class _SyncedLyricsViewState extends State<SyncedLyricsView>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final ItemScrollController _itemScrollController = ItemScrollController();
  int _currentIndex = 0;

  Duration _anchorPos = Duration.zero;
  int _anchorWallMs = 0;
  bool _isPlaying = false;
  double _speed = 1.0;

  late final Ticker _frameTicker;
  StreamSubscription<Duration>? _posSub;

  // ── Format-agnostic karaoke renderer state ───────────────────────────────
  List<List<_TimelineWord>> _wordTimelines = const [];
  final _KaraokeLineController _karaokeController = _KaraokeLineController();

  // ── Manual-scroll suppression ──────────────────────────────────────────────
  bool _userIsManualScrolling = false;
  Timer? _scrollResumeTimer;
  Duration? _pendingSeekPos;
  // ── Single merged listenable for all display settings ─────────────────────
  late final Listenable _settingsListenable;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _frameTicker = createTicker(_onFrameTick);

    _settingsListenable = Listenable.merge([
      LyricsSettings.fontSize,
      LyricsSettings.textAlign,
      LyricsSettings.activeColor,
      LyricsSettings.karaokeMode,
    ]);

    _rebuildWordTimelines();

    final s = AudioService.playbackState.value;
    _syncFromPlaybackState(s);
    _anchorPos = s.position;
    _anchorWallMs = DateTime.now().millisecondsSinceEpoch;
    _currentIndex = _computeLineIndex(s.position);
    _activateTimelineForCurrentLine(s.position);

    if (_isPlaying) _frameTicker.start();

    _posSub = AudioService.positionStream.listen(_onPosition);
    AudioService.playbackState.addListener(_onPlaybackState);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToCenter(_currentIndex, animate: false);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        if (_frameTicker.isActive) _frameTicker.stop();

      case AppLifecycleState.resumed:
        final s = AudioService.playbackState.value;
        _syncFromPlaybackState(s);

        if (_isPlaying && !_frameTicker.isActive) _frameTicker.start();

        final currentPos = _interpolatedPosition;
        _maybeUpdateCurrentLine(currentPos, allowBinarySearch: true);
        if (mounted) setState(() {});

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _scrollToCenter(_currentIndex, animate: true);
        });

      default:
        break;
    }
  }

  @override
  void didUpdateWidget(SyncedLyricsView old) {
    super.didUpdateWidget(old);
    if (old.lyrics != widget.lyrics || old.rawLrc != widget.rawLrc) {
      _rebuildWordTimelines();

      final currentPos = _interpolatedPosition;
      _currentIndex = _computeLineIndex(currentPos);
      _activateTimelineForCurrentLine(currentPos);
    }

    if (!old.isVisible && widget.isVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToCenter(_currentIndex, animate: false);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _posSub?.cancel();
    AudioService.playbackState.removeListener(_onPlaybackState);
    _frameTicker.dispose();
    _karaokeController.dispose();
    _scrollResumeTimer?.cancel();
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) => _buildLyricsView(context);
}
