part of '../audio_service.dart';

/// Main facade for all audio playback operations.
///
/// Architecture: Flutter UI → AudioService → Media3PlaybackBridge
///               → Media3PlaybackService (Kotlin) → ExoPlayer
///
/// All state flows from native → Dart via EventChannel streams.
/// Dart manages queue order (shuffle) and index tracking; native ExoPlayer
/// receives the full playlist via setQueue() and advances gaplessly.
class AudioService {
  AudioService._();

  // ── Position stream (native, high-frequency, for lyrics sync) ──────────────
  /// Direct position stream from native ExoPlayer — use for lyrics sync and
  /// any widget that needs sub-second position updates.
  static Stream<Duration> get positionStream => Media3PlaybackBridge.positionStream;

  // ── Playback state (single source of truth) ────────────────────────────────
  static final ValueNotifier<AudioPlaybackState> playbackState =
      ValueNotifier<AudioPlaybackState>(const AudioPlaybackState());

  // ── Dart-side queue state ───────────────────────────────────────────────────
  static List<LocalSong> _playlist = [];
  static int _currentIndex = 0;
  static LoopMode _loopMode = LoopMode.off;
  static bool _shuffleEnabled = false;
  static List<int> _shuffleOrder = [];

  /// Last song played — used by [LoudnessSourceResolver] for auto album-gain.
  static LocalSong? _previousSong;

  // ── Misc ───────────────────────────────────────────────────────────────────
  static bool _initialized = false;
  static bool _isLoading = false;
  static final List<StreamSubscription<dynamic>> _staticSubs = [];

  // ── Convenience getters ────────────────────────────────────────────────────
  static LocalSong? get currentSong => playbackState.value.currentSong;
  static bool get isPlaying => playbackState.value.isPlaying;
  static int get currentIndex => playbackState.value.currentIndex;
  static List<LocalSong> get currentPlaylist => playbackState.value.currentPlaylist;
  static LoopMode get loopMode => playbackState.value.loopMode;
  static bool get shuffleEnabled => playbackState.value.shuffleEnabled;

  /// Exposed for contexts that need the next track index (e.g. UI hints).
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

    // Native playback state → isPlaying + processingState + track completion.
    // Android 11 / MIUI 12: this is the ONLY source of truth for playback state;
    // no AudioPlayer.playerStateStream duplication needed.
    _staticSubs.add(
      Media3PlaybackBridge.playbackStateStream.listen((event) {
        final isPlaying = event['playing'] == true;
        final ps = _parseProcessingState(event['processingState']);
        _setState(playbackState.value.copyWith(
          isPlaying: isPlaying,
          processingState: ps,
        ));
        if (ps == ProcessingState.completed && !_isLoading) {
          LogService.verbose('AudioService', 'Track completed → handling');
          _onTrackCompleted();
        }
      }),
    );

    // Position (200 ms interval from native positionTicker).
    _staticSubs.add(
      Media3PlaybackBridge.positionStream.listen((position) {
        _setState(playbackState.value.copyWith(position: position));
      }),
    );

    // Duration (resolved after metadata load).
    _staticSubs.add(
      Media3PlaybackBridge.durationStream.listen((duration) {
        _setState(playbackState.value.copyWith(duration: duration));
      }),
    );

    // Current track changes driven by native ExoPlayer.
    // Handles both natural gapless progression and Dart-initiated skips.
    _staticSubs.add(
      Media3PlaybackBridge.currentTrackStream.listen(_onNativeCurrentTrackChanged),
    );

    // Audio session ID → attach DSP effects pipeline.
    // On MIUI 12, the audio session ID may change after a brief background
    // period; re-attaching here keeps EQ/loudness in sync.
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

    LogService.log('AudioService', 'Initialized — native Media3 / ExoPlayer');
  }

  static void _onReplayGainSettingChanged() {
    final song = currentSong;
    if (song != null) unawaited(_applyReplayGain(song));
  }

  static void _onSpeedChange() {
    final spd = AudioEffectsService.playbackSpeed.value;
    _setState(playbackState.value.copyWith(speed: spd));
    LogService.verbose('AudioService', 'Speed changed: ${spd.toStringAsFixed(2)}x');
  }

  // ── Native track change handler ────────────────────────────────────────────

  /// Called when the native Media3 player transitions to a new media item.
  /// Syncs [_currentIndex] and [playbackState] with the native index.
  static void _onNativeCurrentTrackChanged(Map<dynamic, dynamic>? trackMap) {
    if (_playlist.isEmpty) return;
    if (trackMap == null) return;

    final nativeIndex = trackMap['index'] as int? ?? -1;
    final nativeId    = trackMap['id'];

    final int resolvedIndex = (nativeIndex >= 0 && nativeIndex < _playlist.length)
        ? nativeIndex
        : _playlist.indexWhere((s) => s.id == nativeId);

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
      return; // already in sync, skip redundant update
    }

    _syncCurrentTrackFromNative(resolvedIndex);
  }

  static void _syncCurrentTrackFromNative(int index) {
    final song = _playlist[index];
    final previousIndex = _currentIndex;
    _currentIndex = index;
    _previousSong = song;

    _setState(playbackState.value.copyWith(
      currentSong:     song,
      currentIndex:    index,
      currentPlaylist: _playlist,
      duration:        song.duration,
    ));

    LogService.log(
      'AudioService',
      'Native advanced → [${index + 1}/${_playlist.length}]: '
      '"${song.title}" — ${song.artist}',
    );

    if (index != previousIndex) unawaited(HistoryService.trackPlay(song));

    // Re-apply DSP after track transition.  Two calls: immediate for effects
    // that update instantly, delayed 350 ms for audio-session re-attach race.
    AudioEffectsService.applyAll();
    Future.delayed(const Duration(milliseconds: 350), AudioEffectsService.applyAll);
    unawaited(_applyReplayGain(song));
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
      LogService.warn(
        'AudioService',
        'playSongAt: invalid args (index=$index, count=${playlist.length})',
      );
      return;
    }

    _isLoading = true;
    final immutablePlaylist = List<LocalSong>.unmodifiable(playlist);
    final selectedSong = immutablePlaylist[index];
    _playlist = immutablePlaylist;
    _currentIndex = index;
    if (_shuffleEnabled) _buildShuffleOrder();

    _setState(playbackState.value.copyWith(
      currentSong:     selectedSong,
      currentIndex:    index,
      currentPlaylist: immutablePlaylist,
      isLoading:       true,
    ));

    try {
      // Send full playlist to native ExoPlayer so it can prebuffer neighbours
      // for seamless gapless playback.
      await Media3PlaybackBridge.setQueue(immutablePlaylist, index);
      await _applyReplayGain(selectedSong);
      if (autoplay) await Media3PlaybackBridge.play();

      LogService.log(
        'AudioService',
        'Now playing [${index + 1}/${immutablePlaylist.length}]: '
        '"${selectedSong.title}" — ${selectedSong.artist}',
      );
      unawaited(HistoryService.trackPlay(selectedSong));
    } catch (e, st) {
      LogService.error('AudioService', 'playSongAt failed: $e', stackTrace: st.toString());
    } finally {
      _previousSong = selectedSong;
      _isLoading = false;
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

  static Future<void> skipNext() async {
    final nextIdx = _nextIndexValue;
    if (nextIdx < 0) {
      LogService.verbose('AudioService', 'skipNext: already at end of queue');
      return;
    }
    _currentIndex = nextIdx;
    final song = _playlist[nextIdx];
    _setState(playbackState.value.copyWith(
      currentSong:  song,
      currentIndex: nextIdx,
    ));
    // setTrack() seeks ExoPlayer to the correct item without reloading the queue.
    // Shuffle order is respected by using Dart's _nextIndexValue, not native skip.
    await Media3PlaybackBridge.setTrack(nextIdx);
    _previousSong = song;
    unawaited(HistoryService.trackPlay(song));
    unawaited(_applyReplayGain(song));
    LogService.log('AudioService', 'Skip → next "${song.title}"');
  }

  static Future<void> skipPrevious() async {
    final pos = playbackState.value.position;
    if (pos.inSeconds > 3) {
      await Media3PlaybackBridge.seek(Duration.zero);
      LogService.verbose('AudioService', 'Skip previous: restarted track');
      return;
    }
    final prevIdx = _prevIndexValue;
    if (prevIdx < 0) {
      await Media3PlaybackBridge.seek(Duration.zero);
      LogService.verbose('AudioService', 'Skip previous: at start, restarted');
      return;
    }
    _currentIndex = prevIdx;
    final song = _playlist[prevIdx];
    _setState(playbackState.value.copyWith(
      currentSong:  song,
      currentIndex: prevIdx,
    ));
    await Media3PlaybackBridge.setTrack(prevIdx);
    _previousSong = song;
    unawaited(HistoryService.trackPlay(song));
    unawaited(_applyReplayGain(song));
    LogService.log('AudioService', 'Skip → previous "${song.title}"');
  }

  static Future<void> playFromCurrentQueue(int index) async {
    if (index < 0 || index >= _playlist.length) return;
    _currentIndex = index;
    final song = _playlist[index];
    _setState(playbackState.value.copyWith(
      currentSong:  song,
      currentIndex: index,
    ));
    await Media3PlaybackBridge.setTrack(index);
    _previousSong = song;
    unawaited(HistoryService.trackPlay(song));
    unawaited(_applyReplayGain(song));
    LogService.log('AudioService', 'Queue jump → [${index + 1}]: "${song.title}"');
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
    // Shuffle order is managed entirely in Dart (using _shuffleOrder).
    // We do NOT enable native ExoPlayer shuffle to avoid conflicting track
    // advancement between Dart's shuffle sequence and ExoPlayer's internal one.
    LogService.log('AudioService', 'Shuffle → ${_shuffleEnabled ? "on" : "off"}');
  }

  // ── Queue management ───────────────────────────────────────────────────────

  static void addToQueueNext(LocalSong song) {
    if (_playlist.isEmpty) return;
    final nextPos = (_currentIndex + 1).clamp(0, _playlist.length);
    final newList = List<LocalSong>.from(_playlist)..insert(nextPos, song);
    _playlist = List<LocalSong>.unmodifiable(newList);
    if (_shuffleEnabled) _buildShuffleOrder();
    _setState(playbackState.value.copyWith(currentPlaylist: _playlist));
    LogService.log('AudioService', 'Queued next: "${song.title}" at position ${nextPos + 1}');
  }

  static void addToQueue(LocalSong song) {
    if (_playlist.isEmpty) return;
    final newList = List<LocalSong>.from(_playlist)..add(song);
    _playlist = List<LocalSong>.unmodifiable(newList);
    if (_shuffleEnabled) _buildShuffleOrder();
    _setState(playbackState.value.copyWith(currentPlaylist: _playlist));
    LogService.log('AudioService', 'Queued at end: "${song.title}" (queue: ${_playlist.length})');
  }

  /// Reorders the queue by moving the item at [oldIndex] to [newIndex].
  /// Follows Flutter's [ReorderableListView.onReorder] convention.
  static void reorderQueue(int oldIndex, int newIndex) {
    if (_playlist.length < 2) return;
    if (oldIndex == newIndex) return;
    if (oldIndex < 0 || oldIndex >= _playlist.length) return;

    final adjustedNew = (newIndex > oldIndex ? newIndex - 1 : newIndex)
        .clamp(0, _playlist.length - 1);

    final mutable = List<LocalSong>.from(_playlist);
    final item = mutable.removeAt(oldIndex);
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
    if (_shuffleEnabled) _buildShuffleOrder();

    _setState(playbackState.value.copyWith(
      currentPlaylist: _playlist,
      currentIndex:    _currentIndex,
    ));
    LogService.log('AudioService', 'Queue reordered: [$oldIndex] → [$adjustedNew]');
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
    _setState(playbackState.value.copyWith(
      currentSong:  song,
      currentIndex: _currentIndex,
      isLoading:    true,
    ));

    try {
      await Media3PlaybackBridge.setQueue(_playlist, _currentIndex);
      await _applyReplayGain(song);
      if (autoplay) await Media3PlaybackBridge.play();

      LogService.log(
        'AudioService',
        'Now playing [${_currentIndex + 1}/${_playlist.length}]: '
        '"${song.title}" — ${song.artist}',
      );
      unawaited(HistoryService.trackPlay(song));
    } catch (e, st) {
      LogService.error('AudioService', '_playCurrentSong failed: $e', stackTrace: st.toString());
    } finally {
      _previousSong = song;
      _isLoading = false;
      _setState(playbackState.value.copyWith(isLoading: false));
    }
  }

  // ── Track-completed handler ────────────────────────────────────────────────

  /// Called when native ExoPlayer emits [ProcessingState.completed].
  ///
  /// With a full playlist loaded in ExoPlayer, "completed" only fires when the
  /// LAST track ends without loop.  Between-track advancement fires
  /// [_onNativeCurrentTrackChanged] instead — no Dart handling needed.
  static void _onTrackCompleted() {
    if (_isLoading) return;

    if (_loopMode == LoopMode.one) {
      // ExoPlayer handles loop-one natively via setRepeatMode("one"); this
      // fallback covers edge cases where that mode wasn't propagated in time.
      unawaited(Media3PlaybackBridge.seek(Duration.zero));
      unawaited(Media3PlaybackBridge.play());
      LogService.verbose('AudioService', 'Loop one: restarted track');
      return;
    }

    final nextIdx = _nextIndexValue;
    if (nextIdx < 0) {
      LogService.verbose('AudioService', 'End of queue reached');
      return;
    }

    // Loop-all with the full queue already in ExoPlayer: ExoPlayer loops
    // automatically; _onNativeCurrentTrackChanged keeps Dart in sync.
    // This branch fires only if native state diverged — resync manually.
    _currentIndex = nextIdx;
    unawaited(_playCurrentSong(autoplay: true));
  }

  // ── Shuffle helpers ────────────────────────────────────────────────────────

  static void _buildShuffleOrder() {
    _shuffleOrder = List.generate(_playlist.length, (i) => i)..shuffle();
    _shuffleOrder.remove(_currentIndex);
    _shuffleOrder.insert(0, _currentIndex);
  }

  // ── ReplayGain ────────────────────────────────────────────────────────────

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

  // ── Native state synchronization ───────────────────────────────────────────

  /// Pulls the current playback state from the running native Media3 service
  /// and rebuilds the Dart-side [playbackState] and internal playlist.
  ///
  /// Call after [initialize()] and on every [AppLifecycleState.resumed] event.
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

      final ProcessingState ps = _parseProcessingState(stateStr);

      _playlist     = List<LocalSong>.unmodifiable(songs);
      _currentIndex = index;

      final song = songs[index];

      _setState(playbackState.value.copyWith(
        currentSong:     song,
        currentIndex:    index,
        currentPlaylist: _playlist,
        isPlaying:       isPlaying,
        processingState: ps,
        duration: durationMs > 0
            ? Duration(milliseconds: durationMs)
            : song.duration,
        position: Duration(milliseconds: positionMs),
      ));

      LogService.log(
        'AudioService',
        'syncFromNative: restored "${song.title}" — ${song.artist} '
        '[${index + 1}/${songs.length}] '
        'playing=$isPlaying pos=${positionMs}ms',
      );
    } catch (e, st) {
      LogService.warn('AudioService', 'syncFromNative failed: $e\n$st');
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static ProcessingState _parseProcessingState(Object? value) =>
      switch (value) {
        'loading'   => ProcessingState.loading,
        'buffering' => ProcessingState.buffering,
        'ready'     => ProcessingState.ready,
        'completed' => ProcessingState.completed,
        _           => ProcessingState.idle,
      };

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
      currentSong:     _kFakeSong,
      isPlaying:       false,
      currentIndex:    0,
      currentPlaylist: const [_kFakeSong],
      duration:        const Duration(minutes: 3, seconds: 30),
    );
  }

  static void debugClearFake() {
    if (debugFakePlaying) {
      playbackState.value = const AudioPlaybackState();
    }
  }

  // ── Dispose ────────────────────────────────────────────────────────────────

  static Future<void> dispose() async {
    AudioEffectsService.playbackSpeed.removeListener(_onSpeedChange);
    AudioEffectsService.replayGainMode.removeListener(_onReplayGainSettingChanged);
    AudioEffectsService.replayGainPreamp.removeListener(_onReplayGainSettingChanged);
    for (final sub in _staticSubs) {
      await sub.cancel();
    }
    _staticSubs.clear();
    _initialized = false;
    LogService.log('AudioService', 'Disposed');
    await AudioEngine.dispose();
  }
}
