part of '../audio_service.dart';

/// Main facade for all audio playback operations.
///
/// Architecture (native-first):
///   Flutter UI → AudioService → Media3PlaybackBridge
///              → Media3PlaybackService.kt → ExoPlayer
///
/// Native owns: queue, shuffle order, repeat mode, sleep timer, crossfade,
///              all audio effects, and persistence.
/// Flutter owns: AudioPlaybackState (mirror built from EventChannel streams)
///               and the raw LocalSong model objects.
///
/// All state flows native → Dart via EventChannels.
/// Dart never computes shuffle/repeat/next-index independently.
class AudioService {
  AudioService._();

  // ── Position stream (native, high-frequency, for lyrics sync) ─────────────
  static Stream<Duration> get positionStream => Media3PlaybackBridge.positionStream;

  // ── Playback state (single source of truth) ───────────────────────────────
  static final ValueNotifier<AudioPlaybackState> playbackState =
      ValueNotifier<AudioPlaybackState>(const AudioPlaybackState());

  // ── Local playlist mirror ──────────────────────────────────────────────────
  // Kept as a Dart list purely for LocalSong object access (song.duration,
  // ReplayGain data, etc.).  The AUTHORITATIVE queue lives in native.
  static List<LocalSong> _playlist = [];
  static int             _currentIndex = 0;

  /// Last song played — for LoudnessSourceResolver album-gain auto-mode.
  static LocalSong? _previousSong;

  // ── Misc ───────────────────────────────────────────────────────────────────
  static bool _initialized = false;
  static bool _isLoading   = false;
  static final List<StreamSubscription<dynamic>> _staticSubs = [];

  // ── Convenience getters ───────────────────────────────────────────────────
  static LocalSong? get currentSong     => playbackState.value.currentSong;
  static bool       get isPlaying       => playbackState.value.isPlaying;
  static int        get currentIndex    => playbackState.value.currentIndex;
  static List<LocalSong> get currentPlaylist => playbackState.value.currentPlaylist;
  static LoopMode   get loopMode        => playbackState.value.loopMode;
  static bool       get shuffleEnabled  => playbackState.value.shuffleEnabled;

  /// Next queue index (linear only — shuffle order is native/opaque).
  static int get nextIndex {
    final state = playbackState.value;
    final sz    = state.currentPlaylist.length;
    if (sz == 0) return -1;
    if (state.loopMode == LoopMode.one) return state.currentIndex;
    if (state.currentIndex < sz - 1)    return state.currentIndex + 1;
    if (state.loopMode == LoopMode.all) return 0;
    return -1;
  }

  // ── Initialization ────────────────────────────────────────────────────────

  static void initialize() {
    if (_initialized) return;
    _initialized = true;

    // ── Native playback state ─────────────────────────────────────────────
    _staticSubs.add(
      Media3PlaybackBridge.playbackStateStream.listen((event) {
        final isPlaying = event['playing'] == true;
        final ps        = _parseProcessingState(event['processingState']);
        _setState(playbackState.value.copyWith(
          isPlaying:       isPlaying,
          processingState: ps,
        ));
        if (ps == ProcessingState.completed && !_isLoading) {
          LogService.verbose('AudioService', 'Track completed (queue ended)');
          _onTrackCompleted();
        }
      }),
    );

    // ── Position ticker ───────────────────────────────────────────────────
    _staticSubs.add(
      Media3PlaybackBridge.positionStream.listen((position) {
        _setState(playbackState.value.copyWith(position: position));
      }),
    );

    // ── Duration ──────────────────────────────────────────────────────────
    _staticSubs.add(
      Media3PlaybackBridge.durationStream.listen((duration) {
        _setState(playbackState.value.copyWith(duration: duration));
      }),
    );

    // ── Current track (native gapless + Dart-initiated skips) ─────────────
    _staticSubs.add(
      Media3PlaybackBridge.currentTrackStream.listen(_onNativeCurrentTrackChanged),
    );

    // ── Full queue (pushed after every mutation) ──────────────────────────
    _staticSubs.add(
      Media3PlaybackBridge.queueStream.listen(_onNativeQueueChanged),
    );

    // ── Shuffle mode (native ExoPlayer shuffleModeEnabled) ────────────────
    _staticSubs.add(
      Media3PlaybackBridge.shuffleModeStream.listen((enabled) {
        _setState(playbackState.value.copyWith(shuffleEnabled: enabled));
        LogService.verbose('AudioService', 'Shuffle → ${enabled ? "on" : "off"}');
      }),
    );

    // ── Repeat mode (native ExoPlayer REPEAT_MODE_*) ──────────────────────
    _staticSubs.add(
      Media3PlaybackBridge.repeatModeStream.listen((mode) {
        final lm = _loopModeFromString(mode);
        _setState(playbackState.value.copyWith(loopMode: lm));
        LogService.verbose('AudioService', 'Repeat → $mode');
      }),
    );

    // ── Sleep timer ────────────────────────────────────────────────────────
    _staticSubs.add(
      Media3PlaybackBridge.sleepTimerStream.listen((map) {
        final active      = map['active']      as bool? ?? false;
        final remainingMs = (map['remainingMs'] as num?)?.toInt() ?? 0;
        _setState(playbackState.value.copyWith(
          sleepTimerActive:      active,
          sleepTimerRemainingMs: remainingMs,
        ));
      }),
    );

    // ── Audio session ID → attach DSP pipeline ────────────────────────────
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _staticSubs.add(
        Media3PlaybackBridge.audioSessionIdStream.listen(
          AudioEngine.attachEffectsToSession,
        ),
      );
    }

    AudioEffectsService.playbackSpeed.addListener(_onSpeedChange);
    AudioEffectsService.replayGainMode.addListener(_onReplayGainSettingChanged);
    AudioEffectsService.replayGainPreamp.addListener(_onReplayGainSettingChanged);

    LogService.log('AudioService', 'Initialized — native Media3 / ExoPlayer (native-first)');
  }

  static void _onReplayGainSettingChanged() {
    final song = currentSong;
    if (song != null) {
      // LOW-06 fix: errors from the async resolve are logged instead of silently dropped.
      _applyReplayGain(song).catchError((Object e) {
        LogService.warn('AudioService', '_applyReplayGain (setting change) error: $e');
      });
    }
  }

  static void _onSpeedChange() {
    final spd = AudioEffectsService.playbackSpeed.value;
    _setState(playbackState.value.copyWith(speed: spd));
    LogService.verbose('AudioService', 'Speed → ${spd.toStringAsFixed(2)}x');
  }

  // ── Native event handlers ─────────────────────────────────────────────────

  /// Queue updated from native (after setQueue / insertNext / appendToQueue /
  /// removeFromQueue / reorderQueue).
  static void _onNativeQueueChanged(List<dynamic> rawQueue) {
    try {
      final songs = rawQueue
          .whereType<Map>()
          .map((m) => LocalSong.fromMap(m.cast<dynamic, dynamic>()))
          .toList();
      // MED-02 fix: propagate empty queue so Flutter state reflects the cleared
      // playlist rather than keeping a stale list from the previous session.
      if (songs.isEmpty) {
        _playlist = List<LocalSong>.unmodifiable([]);
        _setState(playbackState.value.copyWith(currentPlaylist: const []));
        ArtworkRepository.setActiveQueueIds([]);
        return;
      }
      _playlist = List<LocalSong>.unmodifiable(songs);
      _setState(playbackState.value.copyWith(currentPlaylist: _playlist));

      // Tell the native artwork cache which songs are in the active queue so
      // those WebP files are never evicted by LRU cleanup.
      ArtworkRepository.setActiveQueueIds(songs.map((s) => s.id).toList());
    } catch (e) {
      LogService.warn('AudioService', 'onNativeQueueChanged parse error: $e');
    }
  }

  /// Track changed — driven by native ExoPlayer (gapless, skip, or queue jump).
  static void _onNativeCurrentTrackChanged(Map<dynamic, dynamic>? trackMap) {
  if (_playlist.isEmpty || trackMap == null) return;

  final nativeIndex = trackMap['index'] as int? ?? -1;
  final nativeId    = trackMap['id'];

  final int resolved = (nativeIndex >= 0 && nativeIndex < _playlist.length)
      ? nativeIndex
      : _playlist.indexWhere((s) {
          // nativeId bisa String atau int, konversi ke int jika perlu
          if (nativeId is String) {
            final id = int.tryParse(nativeId);
            return id != null && s.id == id;
          } else if (nativeId is int) {
            return s.id == nativeId;
          }
          return false;
        });

  if (resolved < 0 || resolved >= _playlist.length) {
    LogService.warn(
      'AudioService',
      'Unknown native track index=$nativeIndex id=$nativeId — ignoring',
    );
    return;
  }

  // Skip redundant updates.
  if (resolved == _currentIndex &&
      playbackState.value.currentSong?.id == _playlist[resolved].id) {
    return;
  }

  _syncCurrentTrackFromNative(resolved);
}

  static void _syncCurrentTrackFromNative(int index) {
    final song      = _playlist[index];
    final prevIndex = _currentIndex;
    _currentIndex   = index;
    // ARCH-01 fix: capture _previousSong BEFORE overwriting it. The static field
    // was previously written before _applyReplayGain ran, so album-gain auto-mode
    // always compared the current song to itself (wrong). prevSong now carries the
    // correct predecessor into the async resolve call.
    final prevSong  = _previousSong;
    _previousSong   = song;

    _setState(playbackState.value.copyWith(
      currentSong:     song,
      currentIndex:    index,
      currentPlaylist: _playlist,
      duration:        song.duration,
    ));

    LogService.log(
      'AudioService',
      'Native → [${index + 1}/${_playlist.length}]: '
      '"${song.title}" — ${song.artist}',
    );

    if (index != prevIndex) unawaited(HistoryService.trackPlay(song));

    // Re-apply DSP immediately after a track transition.
    // ARCH-02 fix: the previous 350 ms delayed retry is removed. For gapless
    // playback the audio session ID never changes between tracks, so effects
    // are still valid and the immediate call is sufficient. For crossfade, the
    // promoted standby player gets a fresh session and effects are re-attached
    // via onAudioSessionIdChanged → effectsManager.attachEffects() AND via
    // onCrossfadeComplete → effectsManager.attachEffects(newSessionId), making
    // a redundant Dart-side retry unnecessary and wasteful (8-10 MethodChannel
    // calls per track that would all be no-ops on the native side).
    AudioEffectsService.applyAll();
    // LOW-06 fix: chain catchError so async errors surface in logs instead of
    // being silently dropped by the unawaited fire-and-forget pattern.
    _applyReplayGain(song, prevSong: prevSong).catchError((Object e) {
      LogService.warn('AudioService', '_applyReplayGain error: $e');
    });
  }

  // ── Playback ──────────────────────────────────────────────────────────────

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
      LogService.warn(
        'AudioService',
        'playSongAt: invalid args (index=$index, count=${playlist.length})',
      );
      return;
    }

    _isLoading = true;
    final immutable     = List<LocalSong>.unmodifiable(playlist);
    final selectedSong  = immutable[index];
    _playlist           = immutable;
    _currentIndex       = index;

    _setState(playbackState.value.copyWith(
      currentSong:     selectedSong,
      currentIndex:    index,
      currentPlaylist: immutable,
      isLoading:       true,
    ));

    try {
      // Yield I/O bandwidth to the audio decode pipeline by stopping the
      // background metadata pre-scanner before sending the queue to native.
      MediaStoreService.cancelMetadataPrescanner();

      // Send full playlist to native — ExoPlayer owns queue + gapless.
      await Media3PlaybackBridge.setQueue(immutable, index);
      await _applyReplayGain(selectedSong);
      if (autoplay) await Media3PlaybackBridge.play();

      LogService.log(
        'AudioService',
        'Now playing [${index + 1}/${immutable.length}]: '
        '"${selectedSong.title}" — ${selectedSong.artist}',
      );
      unawaited(HistoryService.trackPlay(selectedSong));
    } catch (e, st) {
      LogService.error('AudioService', 'playSongAt failed: $e', stackTrace: st.toString());
    } finally {
      _previousSong = selectedSong;
      _isLoading    = false;
      _setState(playbackState.value.copyWith(isLoading: false));
    }
  }

  static Future<void> play() async {
    initialize();
    await Media3PlaybackBridge.play();
    LogService.verbose('AudioService', 'Resumed playback');
  }

  static Future<void> pause() async {
    initialize();
    final pos = _fmtDur(playbackState.value.position);
    await Media3PlaybackBridge.pause();
    LogService.verbose('AudioService', 'Paused at $pos');
  }

  static Future<void> seek(Duration position) async {
    initialize();
    await Media3PlaybackBridge.seek(position);
    LogService.verbose('AudioService', 'Seek → ${_fmtDur(position)}');
  }

  /// Skip to the next track.  Native ExoPlayer decides the next item,
  /// respecting its own shuffle order when shuffleModeEnabled=true.
  static Future<void> skipNext() async {
    initialize();
    await Media3PlaybackBridge.skipNext();
    LogService.log('AudioService', 'Skip → next');
  }

  /// Skip to the previous track.
  /// MED-06 fix: Dart-side stale-position check removed. ExoPlayer's
  /// seekToPreviousMediaItem() uses the exact native position with a built-in
  /// 3-second threshold (maxSeekToPreviousPositionMs = 3000 ms default), which
  /// is more accurate than using the polled Dart position that may lag by up
  /// to one position-tick interval. This also ensures crossfade and sleep-timer
  /// cancellation always run (handled by handleSkipPrevious in TransportCommands).
  static Future<void> skipPrevious() async {
    initialize();
    await Media3PlaybackBridge.skipPrevious();
    LogService.log('AudioService', 'Skip → previous');
  }

  /// Jump to any item in the current queue without reloading the native queue.
  static Future<void> playFromCurrentQueue(int index) async {
    if (index < 0 || index >= _playlist.length) return;
    _currentIndex = index;
    final song    = _playlist[index];
    _setState(playbackState.value.copyWith(
      currentSong:  song,
      currentIndex: index,
    ));
    await Media3PlaybackBridge.setTrack(index);
    // LOW-05 fix: explicitly start playback after a queue jump. setTrack() only
    // seeks native ExoPlayer to the target index; it does not resume a paused
    // player. Without this call, tapping a queue item while paused would update
    // the UI track but leave the player paused.
    await Media3PlaybackBridge.play();
    _previousSong = song;
    unawaited(HistoryService.trackPlay(song));
    unawaited(_applyReplayGain(song));
    LogService.log('AudioService', 'Queue jump → [${index + 1}]: "${song.title}"');
  }

  // ── Loop / Shuffle (native-delegated) ─────────────────────────────────────

  static Future<void> cycleLoopMode() async {
    initialize();
    final current = playbackState.value.loopMode;
    final next    = switch (current) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    // Optimistic UI update — native confirms via repeatModeStream.
    _setState(playbackState.value.copyWith(loopMode: next));
    await Media3PlaybackBridge.setRepeatMode(next.name);
    LogService.log('AudioService', 'Loop mode → ${next.name}');
  }

  static Future<void> toggleShuffle() async {
    initialize();
    final current = playbackState.value.shuffleEnabled;
    final next    = !current;
    // Optimistic UI update — native confirms via shuffleModeStream.
    _setState(playbackState.value.copyWith(shuffleEnabled: next));
    await Media3PlaybackBridge.setShuffleMode(next);
    LogService.log('AudioService', 'Shuffle → ${next ? "on" : "off"}');
  }

  // ── Queue mutations (native owns the queue) ───────────────────────────────

  /// Insert [song] immediately after the currently playing track.
  static void addToQueueNext(LocalSong song) {
    // Optimistic update for immediate UI feedback.
    if (_playlist.isNotEmpty) {
      final pos     = (_currentIndex + 1).clamp(0, _playlist.length);
      final mutable = List<LocalSong>.from(_playlist)..insert(pos, song);
      _playlist     = List<LocalSong>.unmodifiable(mutable);
      _setState(playbackState.value.copyWith(currentPlaylist: _playlist));
    }
    // Native update — authoritative; queueStream will confirm.
    unawaited(Media3PlaybackBridge.insertNext(song));
    LogService.log('AudioService', 'Queued next: "${song.title}"');
  }

  /// Append [song] at the end of the queue.
  static void addToQueue(LocalSong song) {
    if (_playlist.isNotEmpty) {
      final mutable = List<LocalSong>.from(_playlist)..add(song);
      _playlist     = List<LocalSong>.unmodifiable(mutable);
      _setState(playbackState.value.copyWith(currentPlaylist: _playlist));
    }
    unawaited(Media3PlaybackBridge.appendToQueue(song));
    LogService.log('AudioService', 'Queued at end: "${song.title}" (${_playlist.length})');
  }

  /// Reorder the queue. Follows Flutter's ReorderableListView convention:
  /// [newIndex] is the insert point BEFORE the list is modified.
  static void reorderQueue(int oldIndex, int newIndex) {
    if (_playlist.length < 2 || oldIndex == newIndex) return;
    if (oldIndex < 0 || oldIndex >= _playlist.length) return;

    // Adjust for Flutter's off-by-one in ReorderableListView.onReorder.
    final adjustedNew = (newIndex > oldIndex ? newIndex - 1 : newIndex)
        .clamp(0, _playlist.length - 1);

    final mutable = List<LocalSong>.from(_playlist);
    final item    = mutable.removeAt(oldIndex);
    mutable.insert(adjustedNew, item);

    int newCurrent = _currentIndex;
    if (oldIndex == _currentIndex) {
      newCurrent = adjustedNew;
    } else if (oldIndex < _currentIndex && adjustedNew >= _currentIndex) {
      newCurrent = _currentIndex - 1;
    } else if (oldIndex > _currentIndex && adjustedNew <= _currentIndex) {
      newCurrent = _currentIndex + 1;
    }

    _currentIndex = newCurrent;
    _playlist     = List<LocalSong>.unmodifiable(mutable);
    _setState(playbackState.value.copyWith(
      currentPlaylist: _playlist,
      currentIndex:    _currentIndex,
    ));

    unawaited(Media3PlaybackBridge.reorderQueue(oldIndex, adjustedNew));
    LogService.log('AudioService', 'Queue reordered: [$oldIndex] → [$adjustedNew]');
  }

  // ── Track-completed handler ────────────────────────────────────────────────
  //
  // ExoPlayer emits STATE_ENDED only when the last track ends with
  // REPEAT_MODE_OFF.  All other completions fire onMediaItemTransition,
  // which we handle in _onNativeCurrentTrackChanged.

  static void _onTrackCompleted() {
    if (_isLoading) return;
    // Native already paused — just log.  No Dart-side re-trigger needed.
    LogService.verbose('AudioService', 'End of queue (native stopped)');
    // Restart the background pre-scanner during this idle window so any
    // songs played for the first time during the last session get cached
    // before the user starts the next one.
    MediaStoreService.startMetadataPrescanner();
  }

  // ── ReplayGain ────────────────────────────────────────────────────────────

  /// ARCH-01 fix: accepts [prevSong] to avoid reading the already-overwritten
  /// [_previousSong] static field from inside an async call. Callers that have
  /// already advanced [_previousSong] should pass the captured predecessor here.
  /// Callers that haven't yet overwritten [_previousSong] can omit this param.
  static Future<void> _applyReplayGain(LocalSong song, {LocalSong? prevSong}) async {
    final mode = AudioEffectsService.replayGainMode.value;
    if (mode == ReplayGainMode.off) {
      AudioEngine.applyNormalize(enabled: false);
      return;
    }
    final data = await LoudnessSourceResolver.resolve(
      song:         song,
      mode:         mode,
      previousSong: prevSong ?? _previousSong,
    );
    if (!data.hasData) {
      AudioEngine.applyNormalize(enabled: false);
      return;
    }
    final preamp = AudioEffectsService.replayGainPreamp.value;
    final gainDb = data.safeGain(preamp: preamp);
    AudioEngine.applyNormalize(enabled: true, targetGainMb: gainDb * 100.0);
  }

  // ── State sync (app resume) ───────────────────────────────────────────────

  /// Re-sync Dart state from the running native service.
  /// Call after initialize() and on every AppLifecycleState.resumed.
  static Future<void> syncFromNative() async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android) return;

    try {
      final snapshot = await Media3PlaybackBridge.getPlaybackSnapshot();
      if (snapshot == null) return;

      final rawQueue = snapshot['queue'];
      if (rawQueue == null) return;
      final List<dynamic> queueList = rawQueue is List ? rawQueue : <dynamic>[];
      if (queueList.isEmpty) return;

      final songs = queueList
          .whereType<Map>()
          .map((m) => LocalSong.fromMap(m.cast<dynamic, dynamic>()))
          .toList();
      if (songs.isEmpty) return;

      final index   = ((snapshot['currentIndex'] as num?)?.toInt() ?? 0)
          .clamp(0, songs.length - 1);
      final isPlaying  = snapshot['isPlaying']       as bool?   ?? false;
      final stateStr   = snapshot['processingState'] as String? ?? 'idle';
      final positionMs = (snapshot['positionMs']     as num?)?.toInt() ?? 0;
      final durationMs = (snapshot['durationMs']     as num?)?.toInt() ?? 0;
      final shuffleOn  = snapshot['shuffleEnabled']  as bool?   ?? false;
      final repeatStr  = snapshot['repeatMode']      as String? ?? 'off';
      final timerActive = snapshot['sleepTimerActive'] as bool? ?? false;
      final timerMs    = (snapshot['sleepTimerRemainingMs'] as num?)?.toInt() ?? 0;

      _playlist     = List<LocalSong>.unmodifiable(songs);
      _currentIndex = index;
      final song    = songs[index];

      _setState(playbackState.value.copyWith(
        currentSong:           song,
        currentIndex:          index,
        currentPlaylist:       _playlist,
        isPlaying:             isPlaying,
        processingState:       _parseProcessingState(stateStr),
        duration: durationMs > 0
            ? Duration(milliseconds: durationMs)
            : song.duration,
        position:              Duration(milliseconds: positionMs),
        shuffleEnabled:        shuffleOn,
        loopMode:              _loopModeFromString(repeatStr),
        sleepTimerActive:      timerActive,
        sleepTimerRemainingMs: timerMs,
      ));

      LogService.log(
        'AudioService',
        'syncFromNative: ${songs.length} tracks, idx=$index, '
        'playing=$isPlaying shuffle=$shuffleOn repeat=$repeatStr',
      );

      await _applyReplayGain(song);
    } catch (e, st) {
      LogService.warn('AudioService', 'syncFromNative error: $e\n$st');
    }
  }

  // ── Internal helpers ──────────────────────────────────────────────────────

  static void _setState(AudioPlaybackState state) {
    if (playbackState.value == state) return;
    playbackState.value = state;
  }

  static ProcessingState _parseProcessingState(dynamic raw) => switch (raw) {
    'buffering' => ProcessingState.buffering,
    'ready'     => ProcessingState.ready,
    'completed' => ProcessingState.completed,
    _           => ProcessingState.idle,
  };

  static LoopMode _loopModeFromString(String mode) => switch (mode) {
    'one' => LoopMode.one,
    'all' => LoopMode.all,
    _     => LoopMode.off,
  };

  static String _fmtDur(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
