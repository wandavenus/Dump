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
  // BuildContext of the currently-live internal ScrollablePositionedList
  // Scrollable, captured from the last ScrollNotification. Used by
  // _jumpByDelta (state_scroll.dart) to reach the real ScrollPosition
  // directly instead of going through ScrollOffsetController.animateScroll.
  BuildContext? liveScrollContext;
  // ── Single merged listenable for all display settings ─────────────────────
  late final Listenable _settingsListenable;

  // When the parent switches between the compact and full lyrics viewport,
  // keep the currently visible content anchored to the same pixel offset.
  double? _pendingViewportRestorePixels;
  bool _viewportRestoreScheduled = false;

  void _prepareForViewportResize() {
    final ctx = liveScrollContext;
    if (ctx == null || !ctx.mounted) return;
    final position = Scrollable.maybeOf(ctx)?.position;
    if (position == null || !position.hasPixels) return;
    _pendingViewportRestorePixels = position.pixels;
    if (_viewportRestoreScheduled) return;

    _viewportRestoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewportRestoreScheduled = false;
      if (!mounted) return;

      final targetPixels = _pendingViewportRestorePixels;
      _pendingViewportRestorePixels = null;
      if (targetPixels == null) return;

      final currentContext = liveScrollContext;
      if (currentContext == null || !currentContext.mounted) return;
      final currentPosition = Scrollable.maybeOf(currentContext)?.position;
      if (currentPosition == null || !currentPosition.hasPixels) return;

      final target = targetPixels.clamp(
        currentPosition.minScrollExtent,
        currentPosition.maxScrollExtent,
      );
      if ((currentPosition.pixels - target).abs() > 0.5) {
        currentPosition.jumpTo(target);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    widget.dragHandle?._attach(this);
    WidgetsBinding.instance.addObserver(this);
    _frameTicker = createTicker(_onFrameTick);

    _settingsListenable = Listenable.merge([
      LyricsSettings.fontSize,
      LyricsSettings.lineSpacing,
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

    if (_isPlaying) unawaited(_frameTicker.start());

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

        if (_isPlaying && !_frameTicker.isActive) {
          unawaited(_frameTicker.start());
        }

        final currentPos = _interpolatedPosition;
        _maybeUpdateCurrentLine(currentPos, allowBinarySearch: true);
        if (mounted) setState(() {});

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _scrollToCenter(_currentIndex, animate: true);
        });

      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void didUpdateWidget(SyncedLyricsView old) {
    super.didUpdateWidget(old);
    if (old.dragHandle != widget.dragHandle) {
      old.dragHandle?._detach(this);
      widget.dragHandle?._attach(this);
    }
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
    widget.dragHandle?._detach(this);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_posSub?.cancel() ?? Future<void>.value());
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
