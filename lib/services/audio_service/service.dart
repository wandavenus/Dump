part of '../audio_service.dart';

/// Main facade for all audio playback operations.
///
/// After the Dual-Player upgrade the queue is managed manually here
/// (no ConcatenatingAudioSource).  [DualPlayerManager] preloads the
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

  // Last song played — used by LoudnessSourceResolver for auto album-gain.
  static LocalSong? _previousSong;

  // ── Misc ───────────────────────────────────────────────────────────────────

  static bool _initialized = false;
  static bool _isLoading = false;

  /// Subscriptions that follow the PRIMARY player; cancelled and
  /// re-created every time [DualPlayerManager.promote] fires.
  static final List<StreamSubscription<dynamic>> _playerSubs = [];

  /// Subscriptions that are independent of which player is primary.
  static final List<StreamSubscription<dynamic>> _staticSubs = [];

  // ── Convenience getters ────────────────────────────────────────────────────

  static LocalSong? get currentSong => playbackState.value.currentSong;
  static bool get isPlaying => playbackState.value.isPlaying;
  static int get currentIndex => playbackState.value.currentIndex;
  static List<LocalSong> get currentPlaylist =>
      playbackState.value.currentPlaylist;
  static LoopMode get loopMode => playbackState.value.loopMode;
  static bool get shuffleEnabled => playbackState.value.shuffleEnabled;

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

    // Subscribe to native queue/item transitions before primary-player streams so
    // Media3-driven advances keep the Dart facade in sync.
    _staticSubs.add(
  Media3PlaybackBridge.currentTrackStream.listen(
    _onNativeCurrentTrackChanged,
  ),
);

_staticSubs.add(
  Media3PlaybackBridge.positionStream.listen((position) {
    _setState(
      playbackState.value.copyWith(position: position),
    );
  }),
);

_staticSubs.add(
  Media3PlaybackBridge.durationStream.listen((duration) {
    _setState(
      playbackState.value.copyWith(duration: duration),
    );
  }),
);

// Subscribe to primary player streams.
_resubscribeToPrimaryStreams();

    // Speed is a ValueNotifier — use addListener (not a stream subscription).
    AudioEffectsService.playbackSpeed.addListener(_onSpeedChange);

    // Re-evaluate preload whenever gapless toggle changes.
    AudioEffectsService.gaplessPlayback.addListener(_onGaplessChanged);

    CrossfadeController.initialize();
    _syncPlaybackState();

    // Wire lockscreen / notification controls → our static methods.
    // Done last so no callback fires before the service is fully ready.
    BackgroundAudioHandler.onPlayRequested = play;
    BackgroundAudioHandler.onPauseRequested = pause;
    BackgroundAudioHandler.onSkipNextRequested = skipNext;
    BackgroundAudioHandler.onSkipPrevRequested = skipPrevious;
    BackgroundAudioHandler.onSeekRequested = seek;
    BackgroundAudioHandler.onSetRepeatRequested = cycleLoopMode;
    BackgroundAudioHandler.onSetShuffleRequested = (_) => toggleShuffle();
    // Speed is a ValueNotifier — use addListener (not a stream subscription).

    AudioEffectsService.replayGainMode.addListener(_onReplayGainSettingChanged);
    AudioEffectsService.replayGainPreamp.addListener(
      _onReplayGainSettingChanged,
    );

    LogService.log('AudioService', 'Initialized');
  }

  static void _onReplayGainSettingChanged() {
    final song = currentSong;
    if (song != null) {
      unawaited(_applyReplayGain(song));
    }
  }

  static void _onSpeedChange() {
    final spd = AudioEffectsService.playbackSpeed.value;
    _setState(playbackState.value.copyWith(speed: spd));
    LogService.verbose(
      'AudioService',
      'Speed changed: ${spd.toStringAsFixed(2)}x',
    );
  }

  static void _onGaplessChanged() {
    _schedulePreload();
    LogService.verbose(
      'AudioService',
      'Gapless: ${AudioEffectsService.gaplessPlayback.value ? "on" : "off"}',
    );
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
        _setState(
          playbackState.value.copyWith(
            isPlaying: state.playing,
            processingState: state.processingState,
          ),
        );

        // Keep the notification / lockscreen in sync on every player-state
        // change (play, pause, buffering, completed …) without waiting for
        // an explicit _syncPlaybackState() call site.
        BackgroundAudioHandler.instance?.pushPlaybackState(
          playing: state.playing,
          processingState: state.processingState,
          updatePosition: p.position,
          speed: AudioEffectsService.playbackSpeed.value,
        );

        if (state.processingState == ProcessingState.completed) {
          LogService.verbose('AudioService', 'Track completed → advancing');
          _onTrackCompleted();
        }
      }),
    );

    _playerSubs.add(
      p.durationStream.listen((Duration? duration) {
        _setState(
          playbackState.value.copyWith(duration: duration ?? Duration.zero),
        );
        if (duration != null && duration > Duration.zero) {
          LogService.verbose(
            'AudioService',
            'Duration resolved: ${_fmtDur(duration)}',
          );
        }
      }),
    );

    // Immediately sync from current player state.
    _setState(
      playbackState.value.copyWith(
        isPlaying: p.playing,
        processingState: p.processingState,
        duration: p.duration ?? Duration.zero,
      ),
    );

    // Periodic position correction so the lockscreen seek bar never drifts.
    //
    // Media notifications compute bar position as:
    //   updatePosition + (now - updateTime) * speed
    // which advances automatically while playing.  We only need to correct
    // for buffering gaps or clock skew — every 10 s is sufficient.
    // The subscription is cancelled alongside all other _playerSubs whenever
    // _resubscribeToPrimaryStreams is called again (promotion, dispose).
    _playerSubs.add(
      Stream.periodic(const Duration(seconds: 10)).listen((_) {
        if (!p.playing) return;
        BackgroundAudioHandler.instance?.pushPlaybackState(
          playing: p.playing,
          processingState: p.processingState,
          updatePosition: p.position,
          speed: AudioEffectsService.playbackSpeed.value,
        );
      }),
    );
  }

  static void _onNativeCurrentTrackChanged(Map<dynamic, dynamic>? event) {
    if (event == null || _playlist.isEmpty) return;

    final nativeIndex = (event['index'] as num?)?.toInt();
    final nativeId = (event['id'] as num?)?.toInt();
    final resolvedIndex =
        nativeIndex != null &&
            nativeIndex >= 0 &&
            nativeIndex < _playlist.length
        ? nativeIndex
        : _playlist.indexWhere((song) => song.id == nativeId);

    if (resolvedIndex < 0 || resolvedIndex >= _playlist.length) {
      LogService.warn(
        'AudioService',
        'Ignoring Media3 track event for unknown item '
            '(index=$nativeIndex id=$nativeId)',
      );
      return;
    }

    if (resolvedIndex == _currentIndex &&
        playbackState.value.currentSong?.id == _playlist[resolvedIndex].id) {
      return;
    }

    _syncCurrentTrackFromNative(resolvedIndex);
  }

  static void _syncCurrentTrackFromNative(int index) {
    final song = _playlist[index];
    final previousIndex = _currentIndex;
    _currentIndex = index;

    _setState(
      playbackState.value.copyWith(
        currentSong: song,
        currentIndex: index,
        currentPlaylist: _playlist,
        duration: song.duration,
      ),
    );

    BackgroundAudioHandler.instance?.updateNowPlaying(
      id: song.id.toString(),
      title: song.title,
      artist: song.artist.isNotEmpty ? song.artist : null,
      album: song.album.isNotEmpty ? song.album : null,
      duration: song.duration,
      artUri: song.albumId > 0
          ? Uri.parse('content://media/external/audio/albumart/${song.albumId}')
          : null,
    );

    LogService.log(
      'AudioService',
      'Media3 advanced → [${index + 1}/${_playlist.length}]: '
          '"${song.title}" — ${song.artist}',
    );

    if (index != previousIndex) {
      unawaited(HistoryService.trackPlay(song));
    }

    AudioEffectsService.applyAll();
    Future.delayed(
      const Duration(milliseconds: 350),
      AudioEffectsService.applyAll,
    );
    unawaited(_applyReplayGain(song));
    _previousSong = song;
    _schedulePreload();
    _syncPlaybackState();
  }

  // ── Playback ───────────────────────────────────────────────────────────────

  static Future<void> playSongAt({
    required List<LocalSong> playlist,
    required int index,
    bool autoplay = true,
  }) async {
    initialize();

    if (_isLoading) {
      LogService.verbose(
        'AudioService',
        'playSongAt ignored — already loading',
      );
      return;
    }
    if (playlist.isEmpty || index < 0 || index >= playlist.length) {
      LogService.warn(
        'AudioService',
        'playSongAt: invalid args (index=$index, count=${playlist.length})',
      );
      return;
    }

    _isLoading = true;

    // Reset any active crossfade and discard stale secondary preload so the
    // old next-track buffer cannot bleed into the new playlist.
    CrossfadeController.reset();
    unawaited(DualPlayerManager.cancelPreload());

    final immutablePlaylist = List<LocalSong>.unmodifiable(playlist);
    final selectedSong = immutablePlaylist[index];

    _playlist = immutablePlaylist;
    _currentIndex = index;
    if (_shuffleEnabled) _buildShuffleOrder();

    LogService.log(
      'AudioService',
      'Loading "${selectedSong.title}" — ${selectedSong.artist} '
          '(track ${index + 1}/${playlist.length})',
    );

    _setState(
      playbackState.value.copyWith(
        currentSong: selectedSong,
        currentIndex: index,
        currentPlaylist: immutablePlaylist,
        isLoading: true,
      ),
    );

    try {
      await player.setQueue(immutablePlaylist, index);
      LogService.verbose(
        'AudioService',
        'Media3 queue set (${immutablePlaylist.length} tracks, index=$index)',
      );

      // Push track metadata to the notification / lockscreen.
      BackgroundAudioHandler.instance?.updateNowPlaying(
        id: selectedSong.id.toString(),
        title: selectedSong.title,
        artist: selectedSong.artist.isNotEmpty ? selectedSong.artist : null,
        album: selectedSong.album.isNotEmpty ? selectedSong.album : null,
        duration: selectedSong.duration,
        artUri: selectedSong.albumId > 0
            ? Uri.parse(
                'content://media/external/audio/albumart/${selectedSong.albumId}',
              )
            : null,
      );

      // Apply ReplayGain gain before playback starts.
      await _applyReplayGain(selectedSong);

      if (autoplay) {
        await player.play();
        LogService.verbose('AudioService', 'Autoplay started');
      }
    } catch (e, st) {
      LogService.error(
        'AudioService',
        'playSongAt failed: $e',
        stackTrace: st.toString(),
      );
    } finally {
      _previousSong = selectedSong;
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
    try {
      DualPlayerManager.secondaryPlayer?.pause();
    } catch (_) {}
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

    // Fast-path: secondary already has the correct next track buffered.
    // Promote it directly instead of discarding the buffer and reloading.
    final preloaded = DualPlayerManager.preloadedSong;
    final nextSong = _playlist.elementAtOrNull(nextIdx);
    if (preloaded != null &&
        nextSong != null &&
        preloaded.id == nextSong.id &&
        DualPlayerManager.secondaryPlayer != null) {
      LogService.log(
        'AudioService',
        'Skip next → promote preloaded "${nextSong.title}"',
      );
      // Do NOT pre-advance _currentIndex; _afterPromotion handles it via
      // _nextIndexValue so the index stays consistent.
      await DualPlayerManager.promote(fromCrossfade: false);
      return;
    }

    // Slow-path: secondary missing or stale — reload primary from disk.
    _currentIndex = nextIdx;
    await _playCurrentSong(autoplay: true);
    LogService.log('AudioService', 'Skip → next track (reload)');
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
    LogService.log(
      'AudioService',
      'Queue jump → [${index + 1}]: "${_playlist[index].title}"',
    );
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
    unawaited(Media3PlaybackBridge.setRepeatMode(next.name));
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
    unawaited(Media3PlaybackBridge.setShuffleMode(_shuffleEnabled));
    _schedulePreload();
    LogService.log(
      'AudioService',
      'Shuffle → ${_shuffleEnabled ? "on" : "off"}',
    );
  }

  // ── Queue management ───────────────────────────────────────────────────────

  static void addToQueueNext(LocalSong song) {
    if (_playlist.isEmpty) return;
    final nextPos = (_currentIndex + 1).clamp(0, _playlist.length);
    final newList = List<LocalSong>.from(_playlist)..insert(nextPos, song);
    _playlist = List<LocalSong>.unmodifiable(newList);
    if (_shuffleEnabled) _buildShuffleOrder();
    _setState(playbackState.value.copyWith(currentPlaylist: _playlist));
    _schedulePreload();
    LogService.log(
      'AudioService',
      'Queued next: "${song.title}" at position ${nextPos + 1}',
    );
  }

  static void addToQueue(LocalSong song) {
    if (_playlist.isEmpty) return;
    final newList = List<LocalSong>.from(_playlist)..add(song);
    _playlist = List<LocalSong>.unmodifiable(newList);
    if (_shuffleEnabled) _buildShuffleOrder();
    _setState(playbackState.value.copyWith(currentPlaylist: _playlist));
    _schedulePreload();
    LogService.log(
      'AudioService',
      'Queued at end: "${song.title}" (queue size: ${_playlist.length})',
    );
  }

  /// Reorders the queue by moving the item at [oldIndex] to [newIndex].
  ///
  /// Follows Flutter's [ReorderableListView.onReorder] convention:
  /// when dragging downward, [newIndex] already accounts for the removal
  /// of the item at [oldIndex], so no extra adjustment is needed here —
  /// the caller passes the raw values from [onReorder].
  static void reorderQueue(int oldIndex, int newIndex) {
    if (_playlist.length < 2) return;
    if (oldIndex == newIndex) return;
    if (oldIndex < 0 || oldIndex >= _playlist.length) return;

    // Flutter's ReorderableListView passes newIndex as the position to insert
    // AFTER the old item has been conceptually removed. We must adjust.
    final adjustedNew = (newIndex > oldIndex ? newIndex - 1 : newIndex).clamp(
      0,
      _playlist.length - 1,
    );

    final mutable = List<LocalSong>.from(_playlist);
    final item = mutable.removeAt(oldIndex);
    mutable.insert(adjustedNew, item);

    // Keep _currentIndex pointing at the same song.
    int newCurrent = _currentIndex;
    if (oldIndex == _currentIndex) {
      newCurrent = adjustedNew;
    } else if (oldIndex < _currentIndex && adjustedNew >= _currentIndex) {
      newCurrent = _currentIndex - 1;
    } else if (oldIndex > _currentIndex && adjustedNew <= _currentIndex) {
      newCurrent = _currentIndex + 1;
    }

    _currentIndex = newCurrent;
    _playlist = List<LocalSong>.unmodifiable(mutable);

    if (_shuffleEnabled) _buildShuffleOrder();

    _setState(
      playbackState.value.copyWith(
        currentPlaylist: _playlist,
        currentIndex: _currentIndex,
      ),
    );

    _schedulePreload();
    LogService.log(
      'AudioService',
      'Queue reordered: [$oldIndex] → [$adjustedNew]',
    );
  }

  // ── Internal — playback helpers ────────────────────────────────────────────

  /// Load and optionally play the song at [_currentIndex].
  static Future<void> _playCurrentSong({bool autoplay = true}) async {
    if (_playlist.isEmpty ||
        _currentIndex < 0 ||
        _currentIndex >= _playlist.length) {
      return;
    }

    _isLoading = true;
    final song = _playlist[_currentIndex];

    _setState(
      playbackState.value.copyWith(
        currentSong: song,
        currentIndex: _currentIndex,
        isLoading: true,
      ),
    );

    try {
      await player.setQueue(_playlist, _currentIndex);

      // Push track metadata to the notification / lockscreen.
      // Covers skip-next (slow path), skip-previous, queue-jump, and
      // the gapless-fallback path — all of which call _playCurrentSong.
      BackgroundAudioHandler.instance?.updateNowPlaying(
        id: song.id.toString(),
        title: song.title,
        artist: song.artist.isNotEmpty ? song.artist : null,
        album: song.album.isNotEmpty ? song.album : null,
        duration: song.duration,
        artUri: song.albumId > 0
            ? Uri.parse(
                'content://media/external/audio/albumart/${song.albumId}',
              )
            : null,
      );

      // Apply ReplayGain before playback starts.
      await _applyReplayGain(song);

      if (autoplay) await player.play();

      LogService.log(
        'AudioService',
        'Now playing [${_currentIndex + 1}/${_playlist.length}]: '
            '"${song.title}" — ${song.artist}',
      );
      unawaited(HistoryService.trackPlay(song));
    } catch (e, st) {
      LogService.error(
        'AudioService',
        '_playCurrentSong failed: $e',
        stackTrace: st.toString(),
      );
    } finally {
      _previousSong = song;
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
        loopOne: _loopMode == LoopMode.one,
      );
      return;
    }

    final current = _playlist[_currentIndex];
    final next = _playlist[nextIdx];

    // Respect the gapless toggle: when off, treat every transition as
    // crossfade-eligible (even same-album tracks).
    final gapless =
        AudioEffectsService.gaplessPlayback.value &&
        GaplessAlbumDetector.isGapless(current, next);

    CrossfadeController.updateContext(
      nextIsGapless: gapless,
      loopOne: _loopMode == LoopMode.one,
    );

    unawaited(DualPlayerManager.preloadTrack(next));

    LogService.verbose(
      'AudioService',
      'Preloading "${next.title}" '
          '(${gapless ? "gapless — no crossfade" : "crossfade eligible"})',
    );
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
      _setState(
        playbackState.value.copyWith(
          currentSong: song,
          currentIndex: _currentIndex,
        ),
      );
      unawaited(HistoryService.trackPlay(song));
      LogService.log(
        'AudioService',
        'Promoted → [${_currentIndex + 1}/${_playlist.length}]: '
            '"${song.title}" — ${song.artist}',
      );
      // Update notification with the promoted track's metadata.
      BackgroundAudioHandler.instance?.updateNowPlaying(
        id: song.id.toString(),
        title: song.title,
        artist: song.artist.isNotEmpty ? song.artist : null,
        album: song.album.isNotEmpty ? song.album : null,
        duration: song.duration,
        artUri: song.albumId > 0
            ? Uri.parse(
                'content://media/external/audio/albumart/${song.albumId}',
              )
            : null,
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

    // Apply ReplayGain for the newly promoted song (async, non-blocking).
    if (song != null) unawaited(_applyReplayGain(song));

    // Preload the track after next.
    _schedulePreload();

    // Runtime validation (verbose-logs only; zero overhead when logging off).
    _validatePostPromotion(fromCrossfade, song);
  }

  // ── Post-promotion validation ──────────────────────────────────────────────

  /// Asserts the DSP pipeline and playback state are intact after a player
  /// swap.  All output goes to [LogService.verbose] so it only appears when
  /// the in-app debug log is enabled; there is no runtime overhead otherwise.
  static void _validatePostPromotion(bool fromCrossfade, LocalSong? song) {
    // ── Transition type ───────────────────────────────────────────────────────
    LogService.verbose(
      'Validation',
      '[promotion] type=${fromCrossfade ? "crossfade" : "gapless"} '
          'track=${song != null ? '"${song.title}"' : "(none)"} '
          'index=$_currentIndex/${_playlist.length}',
    );

    final p = AudioEngine.player;

    // ── Gapless / crossfade path ──────────────────────────────────────────────
    // After crossfade the new primary must already be playing.
    // After gapless the primary starts via play() inside _afterPromotion.
    final expectedPlaying = fromCrossfade;
    if (fromCrossfade && !p.playing) {
      LogService.warn(
        'Validation',
        '[crossfade] new primary is NOT playing after promotion — '
            'state=${p.processingState.name}',
      );
    } else {
      LogService.verbose(
        'Validation',
        '[${fromCrossfade ? "crossfade" : "gapless"}] '
            'playing=${p.playing} state=${p.processingState.name} '
            '— ${expectedPlaying == p.playing ? "OK" : "mismatch"}',
      );
    }

    // ── DSP references ────────────────────────────────────────────────────────
    if (AudioEngine.isAndroid) {
      final eqOk = AudioEngine.equalizer != null;
      final leOk = AudioEngine.loudnessEnhancer != null;
      if (!eqOk || !leOk) {
        LogService.warn(
          'Validation',
          '[DSP] references null after promotion — eq=$eqOk le=$leOk '
              '(AudioEngine._onPrimaryChanged may not have fired)',
        );
      } else {
        LogService.verbose('Validation', '[DSP] eq=$eqOk le=$leOk — OK');
      }

      // ── Effect support flags (survive promotion via session re-attach) ─────
      LogService.verbose(
        'Validation',
        '[effects] virt=${AudioEngine.virtualizerSupported} '
            'bass=${AudioEngine.bassBoostSupported} '
            'reverb=${AudioEngine.reverbSupported}',
      );
    }

    // ── ReplayGain ────────────────────────────────────────────────────────────
    LogService.verbose(
      'Validation',
      '[replaygain] mode=${AudioEffectsService.replayGainMode.value.name} '
          'preamp=${AudioEffectsService.replayGainPreamp.value.toStringAsFixed(1)} dB '
          '— will re-apply asynchronously',
    );

    // ── Equalizer enabled state ───────────────────────────────────────────────
    LogService.verbose(
      'Validation',
      '[eq] enabled=${AudioEffectsService.equalizerEnabled.value} '
          'preset=${AudioEffectsService.roomPreset.value}',
    );

    // ── Bass / Loudness / Reverb ──────────────────────────────────────────────
    LogService.verbose(
      'Validation',
      '[dsp-params] bass=${AudioEffectsService.bassBoost.value} '
          'reverb=${AudioEffectsService.reverbPreset.value} '
          'spatial=${AudioEffectsService.spatialAudio.value}',
    );
  }

  // ── ReplayGain application ────────────────────────────────────────────────

  /// Resolves and applies ReplayGain gain for [song].
  ///
  /// If [ReplayGainMode.off], disables normalize. Otherwise resolves the best
  /// available loudness data and applies it via [AudioEngine.applyNormalize].
  static Future<void> _applyReplayGain(LocalSong song) async {
    final mode = AudioEffectsService.replayGainMode.value;
    if (mode == ReplayGainMode.off) {
      AudioEngine.applyNormalize(enabled: false);
      return;
    }

    final data = await LoudnessSourceResolver.resolve(
      song: song,
      mode: mode,
      previousSong: _previousSong,
    );

    if (!data.hasData) {
      AudioEngine.applyNormalize(enabled: false);
      return;
    }

    final preamp = AudioEffectsService.replayGainPreamp.value;
    final gainDb = data.safeGain(preamp: preamp);
    AudioEngine.applyNormalize(enabled: true, targetGainMb: gainDb * 100.0);
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
        'AudioService',
        'Gapless: secondary not ready, loading directly',
      );
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

  // ── Native state synchronization ───────────────────────────────────────────

  /// Pulls the current playback state from the running native Media3 service
  /// and rebuilds the Dart-side [playbackState] and internal playlist.
  ///
  /// Call this:
  ///   1. Once after [AudioService.initialize()] completes in main().
  ///   2. Every time [AppLifecycleState.resumed] fires in app_state.dart.
  ///
  /// This is the primary mechanism for state restoration after the app is
  /// backgrounded and reopened — it does NOT rely on EventChannel events, which
  /// only arrive when the native player transitions to a new state.
  static Future<void> syncFromNative() async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android) return;

    try {
      final snapshot = await Media3PlaybackBridge.getPlaybackSnapshot();
      if (snapshot == null) return;

      final rawQueue = snapshot['queue'];
      if (rawQueue == null) return;

      final List<dynamic> queueList =
          rawQueue is List ? rawQueue : <dynamic>[];
      if (queueList.isEmpty) return;

      final List<LocalSong> songs = queueList
          .whereType<Map>()
          .map((m) => LocalSong.fromMap(m.cast<dynamic, dynamic>()))
          .toList();

      if (songs.isEmpty) return;

      final int index =
          ((snapshot['currentIndex'] as num?)?.toInt() ?? 0)
              .clamp(0, songs.length - 1);
      final bool isPlaying = snapshot['isPlaying'] as bool? ?? false;
      final String stateStr = snapshot['processingState'] as String? ?? 'idle';
      final int positionMs = (snapshot['positionMs'] as num?)?.toInt() ?? 0;
      final int durationMs = (snapshot['durationMs'] as num?)?.toInt() ?? 0;

      final ProcessingState ps = switch (stateStr) {
        'buffering' => ProcessingState.buffering,
        'ready'     => ProcessingState.ready,
        'completed' => ProcessingState.completed,
        _           => ProcessingState.idle,
      };

      // Rebuild Dart-side playlist so subsequent EventChannel events
      // (currentTrack, queue) are no longer ignored by the empty-list guard.
      _playlist      = List<LocalSong>.unmodifiable(songs);
      _currentIndex  = index;

      final song = songs[index];

      _setState(
        playbackState.value.copyWith(
          currentSong:     song,
          currentIndex:    index,
          currentPlaylist: _playlist,
          isPlaying:       isPlaying,
          processingState: ps,
          duration: durationMs > 0
              ? Duration(milliseconds: durationMs)
              : song.duration,
        ),
      );

      // Update BackgroundAudioHandler metadata so lockscreen stays current.
      BackgroundAudioHandler.instance?.updateNowPlaying(
        id:       song.id.toString(),
        title:    song.title,
        artist:   song.artist.isNotEmpty ? song.artist : null,
        album:    song.album.isNotEmpty  ? song.album  : null,
        duration: song.duration,
        artUri:   song.albumId > 0
            ? Uri.parse(
                'content://media/external/audio/albumart/${song.albumId}',
              )
            : null,
      );
      BackgroundAudioHandler.instance?.pushPlaybackState(
        playing:         isPlaying,
        processingState: ps,
        updatePosition:  Duration(milliseconds: positionMs),
        speed:           AudioEffectsService.playbackSpeed.value,
      );

      LogService.log(
        'AudioService',
        'syncFromNative: restored "${song.title}" — ${song.artist} '
        '[${index + 1}/${songs.length}] '
        'playing=$isPlaying pos=${positionMs}ms',
      );
    } catch (e, st) {
      LogService.warn(
        'AudioService',
        'syncFromNative failed: $e\n$st',
      );
    }
  }

  static void _syncPlaybackState() {
    _setState(
      playbackState.value.copyWith(
        isPlaying: player.playing,
        processingState: player.processingState,
      ),
    );
    // Keep the Android notification / lockscreen in sync.
    BackgroundAudioHandler.instance?.pushPlaybackState(
      playing: player.playing,
      processingState: player.processingState,
      updatePosition: player.position,
      speed: AudioEffectsService.playbackSpeed.value,
    );
  }

  static void _setState(AudioPlaybackState state) {
    playbackState.value = state;
  }

  static String _fmtDur(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── Debug fake playback ────────────────────────────────────────────────────

  static const LocalSong _kFakeSong = LocalSong(
    id: -999,
    title: 'Demo — Morph Player',
    artist: 'Debug Mode',
    path: '',
    album: 'Debug Album',
    albumId: 0,
    duration: Duration(minutes: 3, seconds: 30),
  );

  static bool get debugFakePlaying =>
      playbackState.value.currentSong?.id == -999;

  static void debugStartFake() {
    playbackState.value = AudioPlaybackState(
      currentSong: _kFakeSong,
      isPlaying: false,
      currentIndex: 0,
      currentPlaylist: const [_kFakeSong],
      duration: const Duration(minutes: 3, seconds: 30),
    );
  }

  static void debugClearFake() {
    if (debugFakePlaying) {
      playbackState.value = const AudioPlaybackState();
    }
  }

  // ── Dispose ────────────────────────────────────────────────────────────────

  static Future<void> dispose() async {
    CrossfadeController.dispose();
    AudioEffectsService.playbackSpeed.removeListener(_onSpeedChange);
    AudioEffectsService.gaplessPlayback.removeListener(_onGaplessChanged);
    AudioEffectsService.replayGainMode.removeListener(
      _onReplayGainSettingChanged,
    );
    AudioEffectsService.replayGainPreamp.removeListener(
      _onReplayGainSettingChanged,
    );
    for (final sub in [..._playerSubs, ..._staticSubs]) {
      await sub.cancel();
    }
    _playerSubs.clear();
    _staticSubs.clear();
    _initialized = false;
    DualPlayerManager.onPromoted = null;
    // Clear notification handler callbacks.
    BackgroundAudioHandler.onPlayRequested = null;
    BackgroundAudioHandler.onPauseRequested = null;
    BackgroundAudioHandler.onSkipNextRequested = null;
    BackgroundAudioHandler.onSkipPrevRequested = null;
    BackgroundAudioHandler.onSeekRequested = null;
    BackgroundAudioHandler.onStopRequested = null;
    BackgroundAudioHandler.onSetRepeatRequested = null;
    BackgroundAudioHandler.onSetShuffleRequested = null;
    LogService.log('AudioService', 'Disposed');
    await AudioEngine.dispose();
  }
}
