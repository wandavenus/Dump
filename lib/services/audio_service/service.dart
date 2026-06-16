part of '../audio_service.dart';

/// Main facade for all audio playback operations.
///
/// After the Dual-Player upgrade the queue is managed manually here
/// (no [ConcatenatingAudioSource]).  [DualPlayerManager] preloads the
/// next track in a secondary [AudioPlayer]; when a track ends (gapless)
/// or a crossfade completes, [DualPlayerManager.promote] atomically
/// swaps secondary → primary and fires [_afterPromotion].
class AudioService {
  AudioService._();

  // ── Player accessor ────────────────────────────────────────────────────────

  /// Returns the currently active (primary) [AudioPlayer].
  /// Delegates to [AudioEngine.player] → [DualPlayerManager.primaryPlayer].
  static AudioPlayer get player => AudioEngine.player;

  // ── Playback state ─────────────────────────────────────────────────────────

  static final ValueNotifier<AudioPlaybackState> playbackState =
      ValueNotifier<AudioPlaybackState>(const AudioPlaybackState());

  // ── Manual queue state (replaces ConcatenatingAudioSource) ─────────────────

  static List<LocalSong> _playlist = [];
  static int _currentIndex = 0;
  static LoopMode _loopMode = LoopMode.off;
  static bool _shuffleEnabled = false;
  static List<int> _shuffleOrder = [];

  // ── Misc ───────────────────────────────────────────────────────────────────

  static bool _initialized = false;
  static bool _isLoading   = false;

  /// Subscriptions that follow the PRIMARY player; cancelled and
  /// re-created every time [DualPlayerManager.promote] fires.
  static final List<StreamSubscription<dynamic>> _playerSubs = [];

  /// Subscriptions that are independent of which player is primary.
  static final List<StreamSubscription<dynamic>> _staticSubs = [];

  // ── Convenience getters ────────────────────────────────────────────────────

  static LocalSong? get currentSong     => playbackState.value.currentSong;
  static bool       get isPlaying       => playbackState.value.isPlaying;
  static int        get currentIndex    => playbackState.value.currentIndex;
  static List<LocalSong> get currentPlaylist =>
      playbackState.value.currentPlaylist;
  static LoopMode   get loopMode        => playbackState.value.loopMode;
  static bool       get shuffleEnabled  => playbackState.value.shuffleEnabled;

  /// Exposed for [CrossfadeController] so it can populate its gapless
  /// context without importing [AudioService] (avoids circular dep).
  static int get nextIndex => _nextIndexValue;

  // ── Queue navigation helpers ───────────────────────────────────────────────

  static int get _nextIndexValue {
    if (_loopMode == LoopMode.one) return _currentIndex;
    if (_shuffleEnabled && _shuffleOrder.isNotEmpty) {
      final pos = _shuffleOrder.indexOf(_currentIndex);
      if (pos < _shuffleOrder.length - 1) return _shuffleOrder[pos + 1];
      return _loopMode == LoopMode.all ? _shuffleOrder[0] : -1;
    }
    if (_currentIndex < _playlist.length - 1) return _currentIndex + 1;
    return _loopMode == LoopMode.all ? 0 : -1;
  }

  static int get _prevIndexValue {
    if (_loopMode == LoopMode.one) return _currentIndex;
    if (_shuffleEnabled && _shuffleOrder.isNotEmpty) {
      final pos = _shuffleOrder.indexOf(_currentIndex);
      if (pos > 0) return _shuffleOrder[pos - 1];
      return _loopMode == LoopMode.all ? _shuffleOrder.last : -1;
    }
    if (_currentIndex > 0) return _currentIndex - 1;
    return _loopMode == LoopMode.all ? _playlist.length - 1 : -1;
  }

  // ── Initialization ─────────────────────────────────────────────────────────

  static void initialize() {
    if (_initialized) return;
    _initialized = true;

    // Register promotion callback from DualPlayerManager.
    DualPlayerManager.onPromoted = _afterPromotion;

    // Subscribe to primary player streams.
    _resubscribeToPrimaryStreams();

    // Speed is a ValueNotifier — use addListener (not a stream subscription).
    AudioEffectsService.playbackSpeed.addListener(_onSpeedChange);

    CrossfadeController.initialize();
    _syncPlaybackState();
    LogService.log('AudioService', 'Initialized');
  }

  static void _onSpeedChange() {
    final spd = AudioEffectsService.playbackSpeed.value;
    _setState(playbackState.value.copyWith(speed: spd));
    LogService.verbose('AudioService',
        'Speed changed: ${spd.toStringAsFixed(2)}x');
  }

  // ── Primary-stream subscriptions ───────────────────────────────────────────

  /// Cancels current primary-player subscriptions and resubscribes to
  /// [AudioEngine.player] (= [DualPlayerManager.primaryPlayer]).
  /// Called at init and every time a promotion occurs.
  static void _resubscribeToPrimaryStreams() {
    for (final sub in _playerSubs) {
      unawaited(sub.cancel());
    }
    _playerSubs.clear();

    final p = AudioEngine.player;

    _playerSubs.add(
      p.playerStateStream.listen((PlayerState state) {
        _setState(playbackState.value.copyWith(
          isPlaying:       state.playing,
          processingState: state.processingState,
        ));

        if (state.processingState == ProcessingState.completed) {
          LogService.verbose('AudioService', 'Track completed → advancing');
          _onTrackCompleted();
        }
      }),
    );

    _playerSubs.add(
      p.durationStream.listen((Duration? duration) {
        _setState(playbackState.value.copyWith(
          duration: duration ?? Duration.zero,
        ));
        if (duration != null && duration > Duration.zero) {
          LogService.verbose(
              'AudioService', 'Duration resolved: ${_fmtDur(duration)}');
        }
      }),
    );

    // Immediately sync from current player state.
    _setState(playbackState.value.copyWith(
      isPlaying:       p.playing,
      processingState: p.processingState,
      duration:        p.duration ?? Duration.zero,
    ));
  }

  // ── Playback ───────────────────────────────────────────────────────────────

  static Future<void> playSongAt({
    required List<LocalSong> playlist,
    required int index,
    bool autoplay = true,
  }) async {
    initialize();

    if (_isLoading) {
      LogService.verbose('AudioService', 'playSongAt ignored — already loading');
      return;
    }
    if (playlist.isEmpty || index < 0 || index >= playlist.length) {
      LogService.warn('AudioService',
          'playSongAt: invalid args (index=$index, count=${playlist.length})');
      return;
    }

    _isLoading = true;

    // Reset any active crossfade.
    CrossfadeController.reset();

    final immutablePlaylist  = List<LocalSong>.unmodifiable(playlist);
    final selectedSong       = immutablePlaylist[index];

    _playlist      = immutablePlaylist;
    _currentIndex  = index;
    if (_shuffleEnabled) _buildShuffleOrder();

    LogService.log(
      'AudioService',
      'Loading "${selectedSong.title}" — ${selectedSong.artist} '
      '(track ${index + 1}/${playlist.length})',
    );

    _setState(playbackState.value.copyWith(
      currentSong:     selectedSong,
      currentIndex:    index,
      currentPlaylist: immutablePlaylist,
      isLoading:       true,
    ));

    try {
      await player.setAudioSource(buildAudioSource(selectedSong));
      LogService.verbose('AudioService', 'AudioSource set (single-track primary)');

      if (autoplay) {
        await player.play();
        LogService.verbose('AudioService', 'Autoplay started');
      }
    } catch (e, st) {
      LogService.error('AudioService', 'playSongAt failed: $e',
          stackTrace: st.toString());
    } finally {
      _isLoading = false;
      _setState(playbackState.value.copyWith(isLoading: false));
      _syncPlaybackState();
    }

    // Preload next track into secondary player.
    _schedulePreload();
  }

  static Future<void> play() async {
    initialize();
    await player.play();
    LogService.verbose('AudioService', 'Resumed playback');
    _syncPlaybackState();
  }

  static Future<void> pause() async {
    initialize();
    final pos = _fmtDur(player.position);
    await player.pause();
    // Also pause secondary if it was fading in during a crossfade.
    try { DualPlayerManager.secondaryPlayer?.pause(); } catch (_) {}
    LogService.verbose('AudioService', 'Paused at $pos');
    _syncPlaybackState();
  }

  static Future<void> seek(Duration position) async {
    initialize();
    await player.seek(position);
    LogService.verbose('AudioService', 'Seek → ${_fmtDur(position)}');
    _syncPlaybackState();
  }

  static Future<void> skipNext() async {
    final nextIdx = _nextIndexValue;
    if (nextIdx < 0) {
      LogService.verbose('AudioService', 'skipNext: already at end of queue');
      return;
    }
    CrossfadeController.reset();
    _currentIndex = nextIdx;
    await _playCurrentSong(autoplay: true);
    LogService.log('AudioService', 'Skip → next track');
  }

  static Future<void> skipPrevious() async {
    if (player.position.inSeconds > 3) {
      await player.seek(Duration.zero);
      LogService.verbose('AudioService', 'Skip previous: restarted track');
      return;
    }
    final prevIdx = _prevIndexValue;
    if (prevIdx < 0) {
      await player.seek(Duration.zero);
      LogService.verbose('AudioService', 'Skip previous: at start, restarted');
      return;
    }
    CrossfadeController.reset();
    _currentIndex = prevIdx;
    await _playCurrentSong(autoplay: true);
    LogService.log('AudioService', 'Skip → previous track');
  }

  static Future<void> playFromCurrentQueue(int index) async {
    if (index < 0 || index >= _playlist.length) return;
    CrossfadeController.reset();
    _currentIndex = index;
    await _playCurrentSong(autoplay: true);
    LogService.log('AudioService',
        'Queue jump → [${index + 1}]: "${_playlist[index].title}"');
  }

  // ── Loop / Shuffle ─────────────────────────────────────────────────────────

  static Future<void> cycleLoopMode() async {
    final next = switch (_loopMode) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    _loopMode = next;
    _setState(playbackState.value.copyWith(loopMode: next));
    _schedulePreload(); // update preload since "next" may have changed
    LogService.log('AudioService', 'Loop mode → ${next.name}');
  }

  static Future<void> toggleShuffle() async {
    _shuffleEnabled = !_shuffleEnabled;
    if (_shuffleEnabled) {
      _buildShuffleOrder();
    } else {
      _shuffleOrder = [];
    }
    _setState(playbackState.value.copyWith(shuffleEnabled: _shuffleEnabled));
    _schedulePreload();
    LogService.log('AudioService',
        'Shuffle → ${_shuffleEnabled ? "on" : "off"}');
  }

  // ── Queue management ───────────────────────────────────────────────────────

  static void addToQueueNext(LocalSong song) {
    if (_playlist.isEmpty) return;
    final nextPos    = (_currentIndex + 1).clamp(0, _playlist.length);
    final newList    = List<LocalSong>.from(_playlist)..insert(nextPos, song);
    _playlist = List<LocalSong>.unmodifiable(newList);
    if (_shuffleEnabled) _buildShuffleOrder();
    _setState(playbackState.value.copyWith(currentPlaylist: _playlist));
    _schedulePreload();
    LogService.log('AudioService',
        'Queued next: "${song.title}" at position ${nextPos + 1}');
  }

  static void addToQueue(LocalSong song) {
    if (_playlist.isEmpty) return;
    final newList = List<LocalSong>.from(_playlist)..add(song);
    _playlist = List<LocalSong>.unmodifiable(newList);
    if (_shuffleEnabled) _buildShuffleOrder();
    _setState(playbackState.value.copyWith(currentPlaylist: _playlist));
    _schedulePreload();
    LogService.log('AudioService',
        'Queued at end: "${song.title}" (queue size: ${_playlist.length})');
  }

  // ── Internal — playback helpers ────────────────────────────────────────────

  /// Load and optionally play the song at [_currentIndex].
  static Future<void> _playCurrentSong({bool autoplay = true}) async {
    if (_playlist.isEmpty ||
        _currentIndex < 0 ||
        _currentIndex >= _playlist.length) return;

    _isLoading = true;
    final song = _playlist[_currentIndex];

    _setState(playbackState.value.copyWith(
      currentSong:  song,
      currentIndex: _currentIndex,
      isLoading:    true,
    ));

    try {
      await player.setAudioSource(buildAudioSource(song));
      if (autoplay) await player.play();

      LogService.log(
        'AudioService',
        'Now playing [${_currentIndex + 1}/${_playlist.length}]: '
        '"${song.title}" — ${song.artist}',
      );
      unawaited(HistoryService.trackPlay(song));
    } catch (e, st) {
      LogService.error('AudioService', '_playCurrentSong failed: $e',
          stackTrace: st.toString());
    } finally {
      _isLoading = false;
      _setState(playbackState.value.copyWith(isLoading: false));
      _syncPlaybackState();
    }

    _schedulePreload();
  }

  // ── Preloading ─────────────────────────────────────────────────────────────

  /// Preloads the next track into the secondary player and informs
  /// [CrossfadeController] of the gapless-album context.
  static void _schedulePreload() {
    final nextIdx = _nextIndexValue;

    if (nextIdx < 0 ||
        nextIdx == _currentIndex ||
        nextIdx >= _playlist.length) {
      unawaited(DualPlayerManager.cancelPreload());
      CrossfadeController.updateContext(
        nextIsGapless: false,
        loopOne:       _loopMode == LoopMode.one,
      );
      return;
    }

    final current = _playlist[_currentIndex];
    final next    = _playlist[nextIdx];
    final gapless = GaplessAlbumDetector.isGapless(current, next);

    CrossfadeController.updateContext(
      nextIsGapless: gapless,
      loopOne:       _loopMode == LoopMode.one,
    );

    unawaited(DualPlayerManager.preloadTrack(next));

    LogService.verbose('AudioService',
        'Preloading "${next.title}" '
        '(${gapless ? "gapless — no crossfade" : "crossfade eligible"})');
  }

  // ── Promotion callback (fired by DualPlayerManager) ────────────────────────

  /// Called immediately after [DualPlayerManager.promote] swaps the players.
  ///
  /// [fromCrossfade] = true  → secondary was already playing; don't call play().
  /// [fromCrossfade] = false → secondary was preloaded but paused; call play().
  static void _afterPromotion(bool fromCrossfade) {
    // Advance queue index.
    final nextIdx = _nextIndexValue;
    if (nextIdx >= 0 && nextIdx < _playlist.length) {
      _currentIndex = nextIdx;
    }

    final song = _playlist.elementAtOrNull(_currentIndex);
    if (song != null) {
      _setState(playbackState.value.copyWith(
        currentSong:  song,
        currentIndex: _currentIndex,
      ));
      unawaited(HistoryService.trackPlay(song));
      LogService.log(
        'AudioService',
        'Promoted → [${_currentIndex + 1}/${_playlist.length}]: '
        '"${song.title}" — ${song.artist}',
      );
    }

    // Re-subscribe to the new primary's streams.
    _resubscribeToPrimaryStreams();

    // Start playback if secondary was only preloaded (gapless path).
    if (!fromCrossfade) {
      unawaited(DualPlayerManager.primaryPlayer.play());
    }

    // Re-apply DSP effects immediately (EQ, pitch, speed).
    AudioEffectsService.applyAll();
    // Re-apply native effects (BassBoost, Reverb, Spatial) once the new
    // audio session has settled (~350 ms — avoids race with session ID).
    Future.delayed(
      const Duration(milliseconds: 350),
      AudioEffectsService.applyAll,
    );

    // Preload the track after next.
    _schedulePreload();
  }

  // ── Track-completed handler ────────────────────────────────────────────────

  static void _onTrackCompleted() {
    if (_isLoading) return;

    // CrossfadeController is handling this transition.
    if (CrossfadeController.isFading) return;

    if (_loopMode == LoopMode.one) {
      player.seek(Duration.zero).then((_) => player.play());
      LogService.verbose('AudioService', 'Loop one: restarting track');
      return;
    }

    final nextIdx = _nextIndexValue;
    if (nextIdx < 0) {
      LogService.verbose('AudioService', 'End of queue reached');
      return;
    }

    // Gapless promotion: secondary is preloaded → promote then play.
    unawaited(_gaplessPromoteAndPlay());
  }

  static Future<void> _gaplessPromoteAndPlay() async {
    if (DualPlayerManager.secondaryPlayer == null) {
      // Fallback: secondary wasn't ready — load track directly.
      LogService.warn(
          'AudioService', 'Gapless: secondary not ready, loading directly');
      _currentIndex = _nextIndexValue;
      await _playCurrentSong(autoplay: true);
      return;
    }
    // Promote secondary → primary (not from crossfade, so play() is needed).
    await DualPlayerManager.promote(fromCrossfade: false);
    // _afterPromotion(false) will call play() on the new primary.
  }

  // ── Shuffle helpers ────────────────────────────────────────────────────────

  static void _buildShuffleOrder() {
    _shuffleOrder = List.generate(_playlist.length, (i) => i)..shuffle();
    // Ensure current track stays at the logical "front".
    _shuffleOrder.remove(_currentIndex);
    _shuffleOrder.insert(0, _currentIndex);
  }

  // ── Misc internals ─────────────────────────────────────────────────────────

  static void _syncPlaybackState() {
    _setState(playbackState.value.copyWith(
      isPlaying:       player.playing,
      processingState: player.processingState,
    ));
  }

  static void _setState(AudioPlaybackState state) {
    playbackState.value = state;
  }

  static String _fmtDur(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── Dispose ────────────────────────────────────────────────────────────────

  static Future<void> dispose() async {
    CrossfadeController.dispose();
    AudioEffectsService.playbackSpeed.removeListener(_onSpeedChange);
    for (final sub in [..._playerSubs, ..._staticSubs]) {
      await sub.cancel();
    }
    _playerSubs.clear();
    _staticSubs.clear();
    _initialized = false;
    DualPlayerManager.onPromoted = null;
    LogService.log('AudioService', 'Disposed');
    await AudioEngine.dispose();
  }
}
