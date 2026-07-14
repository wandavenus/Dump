part of '../audio_service.dart';

/// Main facade for all audio playback operations.
///
/// Architecture:
///   Flutter UI
///     ↓
///   AudioService              (this class — business-logic facade)
///     ↓
///   PlaybackManager           (stream routing + artwork prefetch)
///     ↓
///   Media3PlaybackBridge      (sole MethodChannel / EventChannel edge)
///     ↓
///   Media3PlaybackService.kt  → ExoPlayer
///
/// Native (Media3) owns: queue, shuffle order, repeat mode, sleep timer,
///                       crossfade, all audio effects, and persistence.
/// Flutter owns: AudioPlaybackState (mirror built from engine streams)
///               and the raw LocalSong model objects.
///
/// All state flows native → Media3PlaybackBridge → PlaybackManager → Dart
/// via forwarding streams.  Dart never computes shuffle/repeat/next-index
/// independently.
class AudioService {
  AudioService._();

  // ── Position stream (engine-agnostic, high-frequency, for lyrics sync) ─────
  static Stream<Duration> get positionStream => PlaybackManager.positionStream;

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

  // ── Misc ─────────────────────────────────────────────────────────────[...]
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

  /// Next queue index — shuffle-correct when native value is available.
  ///
  /// Returns [AudioPlaybackState.nextTrackIndex] when native has reported it
  /// (i.e., it is non-null), which respects ExoPlayer's internal shuffle order
  /// and repeat mode exactly. Falls back to linear calculation only before the
  /// first native `currentTrack` event arrives (cold start / initial load).
  ///
  /// Values:
  ///   `>= 0` — actual next index into [AudioService.currentPlaylist].
  ///   `-1`   — no next track (end of queue with repeat off).
  static int get nextIndex {
    final nativeNext = playbackState.value.nextTrackIndex;
    if (nativeNext != null) return nativeNext;
    // Fallback: linear calculation (used before first native currentTrack event).
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
    BootTrace.log('ENTER AudioService.initialize()');
    if (_initialized) {
      BootTrace.log('EXIT  AudioService.initialize() — already initialized, no-op');
      return;
    }
    _initialized = true;

    // ── Engine playback state ─────────────────────────────────────────────
    _staticSubs.add(
      PlaybackManager.playbackStateStream.listen((event) {
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
      PlaybackManager.positionStream.listen((position) {
        _setState(playbackState.value.copyWith(position: position));
      }),
    );

    // ── Duration ───────────────────────────────────────────────────────────[...]
    _staticSubs.add(
      PlaybackManager.durationStream.listen((duration) {
        _setState(playbackState.value.copyWith(duration: duration));
      }),
    );

    // ── Current track ──────────────────────────────────────────────────────
    _staticSubs.add(
      PlaybackManager.currentTrackStream.listen(_onNativeCurrentTrackChanged),
    );

    // ── Full queue (pushed after every mutation) ──────────────────────────
    _staticSubs.add(
      PlaybackManager.queueStream.listen(_onNativeQueueChanged),
    );

    // ── Shuffle mode ──────────────────────────────────────────────────────
    _staticSubs.add(
      PlaybackManager.shuffleModeStream.listen((enabled) {
        _setState(playbackState.value.copyWith(shuffleEnabled: enabled));
        LogService.verbose('AudioService', 'Shuffle → ${enabled ? "on" : "off"}');
      }),
    );

    // ── Repeat mode ───────────────────────────────────────────────────────
    _staticSubs.add(
      PlaybackManager.repeatModeStream.listen((mode) {
        final lm = _loopModeFromString(mode);
        _setState(playbackState.value.copyWith(loopMode: lm));
        LogService.verbose('AudioService', 'Repeat → $mode');
      }),
    );

    // ── Sleep timer ────────────────────────────────────────────────────────
    _staticSubs.add(
      PlaybackManager.sleepTimerStream.listen((map) {
        final active      = map['active']      as bool? ?? false;
        final remainingMs = (map['remainingMs'] as num?)?.toInt() ?? 0;
        _setState(playbackState.value.copyWith(
          sleepTimerActive:      active,
          sleepTimerRemainingMs: remainingMs,
        ));
      }),
    );

    // ── Audio session ID → attach DSP pipeline (Media3 only) ─────────────
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _staticSubs.add(
        PlaybackManager.audioSessionIdStream.listen((id) {
          if (id > 0) DeviceDsp.attachEffectsToSession(id);
        }),
      );
    }

    // ── Audio format → sync sample rate to Loudness Normalization DSP ────────
    // loudness_processor.c initialises its K-weighting biquad filters for
    // 48 kHz.  Without this subscriber, playing a 44.1 kHz file would keep
    // the wrong coefficients, producing inaccurate LUFS readings and therefore
    // a wrong normalisation gain.  audioFormatStream fires on every track
    // change when ExoPlayer's renderer configures a new AudioTrack.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _staticSubs.add(
        PlaybackManager.audioFormatStream.listen((event) {
          final sr = (event['sampleRate'] as num?)?.toInt() ?? 0;
          if (sr > 0 && PlaybackManager.nativeLoudnessNormAvailable) {
            PlaybackManager.setNativeLoudnessSampleRate(sr);
          }
          // Native Parametric EQ (Phase 5) biquad coefficients are also
          // sample-rate dependent — keep them in sync the same way.
          if (sr > 0 && PlaybackManager.nativePeqAvailable) {
            AudioEffectsService.setPeqSampleRateHint(sr);
          }
        }),
      );
    }

    AudioEffectsService.playbackSpeed.addListener(_onSpeedChange);
    AudioEffectsService.replayGainMode.addListener(_onReplayGainSettingChanged);
    AudioEffectsService.replayGainPreamp.addListener(_onReplayGainSettingChanged);
    AudioEffectsService.clippingProtection.addListener(_onReplayGainSettingChanged);

    // Loudness Normalization (Phase 8.5) — sync initial state to native layer.
    //
    // Fail-open, matching PlaybackManager.initialize()'s handling of
    // NativeDspPipeline.instance.initialize(): only touch bindings.* once the
    // native DSP runtime has actually finished initializing successfully, and
    // never let a native-runtime failure here (e.g. a dlopen failure) escape
    // this synchronous, unguarded call site and abort AudioService.initialize()
    // before runApp() — that would silently prevent Home from ever rendering.
    if (PlaybackManager.nativeLoudnessNormAvailable) {
      try {
        PlaybackManager.setNativeLoudnessNormBypass(
            !AudioEffectsService.loudnessNormEnabled.value);
        PlaybackManager.setNativeLoudnessNormTargetLufs(
            AudioEffectsService.loudnessNormTarget.value);
      } catch (e, st) {
        LogService.error('AudioService',
            'Loudness Normalization sync failed despite native runtime reporting available: $e',
            stackTrace: st.toString());
      }
    } else {
      LogService.log('AudioService',
          'Loudness Normalization skipped — native DSP runtime unavailable '
          '(loudnessNormEnabled will have no effect until the native runtime loads)');
    }

    LogService.log('AudioService', 'Initialized — engine: Native Media3');
    BootTrace.log('EXIT  AudioService.initialize()');
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

    // Extract native next-track index (respects shuffle order + repeat mode).
    //   Field present, value int  → use native value (>= 0) or -1 (no next item).
    //   Field present, value null → no next item; -1.
    //   Field absent              → old native build; null triggers linear fallback.
    final int? nativeNext;
    if (trackMap.containsKey('nextTrackIndex')) {
      final v = trackMap['nextTrackIndex'];
      nativeNext = v is int ? v : -1;
    } else {
      nativeNext = null;
    }

    // Skip full sync when the current track hasn't changed, but still update
    // nextTrackIndex in state — it changes after queue reorders, shuffle toggles,
    // and repeat-mode changes even if the currently-playing track is the same.
    if (resolved == _currentIndex &&
        playbackState.value.currentSong?.id == _playlist[resolved].id) {
      if (nativeNext != playbackState.value.nextTrackIndex) {
        _setState(playbackState.value.copyWith(
          nextTrackIndex:      nativeNext,
          clearNextTrackIndex: nativeNext == null,
        ));
      }
      return;
    }

    _syncCurrentTrackFromNative(resolved, nativeNextIndex: nativeNext);
  }

  static void _syncCurrentTrackFromNative(int index, {int? nativeNextIndex}) {
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
      currentSong:         song,
      currentIndex:        index,
      currentPlaylist:     _playlist,
      duration:            song.duration,
      nextTrackIndex:      nativeNextIndex,
      clearNextTrackIndex: nativeNextIndex == null,
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
    // Reset loudness analyzer on each track change so the new track is
    // measured fresh (prevents stale gain from the previous song carrying over).
    if (AudioEffectsService.loudnessNormEnabled.value) {
      PlaybackManager.resetNativeLoudnessNorm();
    }
    // LOW-06 fix: chain catchError so async errors surface in logs instead of
    // being silently dropped by the unawaited fire-and-forget pattern.
    _applyReplayGain(song, prevSong: prevSong).catchError((Object e) {
      LogService.warn('AudioService', '_applyReplayGain error: $e');
    });
  }

  // ── Playback ──────────────────────────────────────────────────────────[...]

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

      // Kirim playlist ke engine aktif.
      await PlaybackManager.setQueue(immutable, index);
      await _applyReplayGain(selectedSong);
      if (autoplay) await PlaybackManager.play();

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
    await PlaybackManager.play();
    LogService.verbose('AudioService', 'Resumed playback');
  }

  static Future<void> pause() async {
    initialize();
    final pos = _fmtDur(playbackState.value.position);
    await PlaybackManager.pause();
    LogService.verbose('AudioService', 'Paused at $pos');
  }

  static Future<void> seek(Duration position) async {
    initialize();
    await PlaybackManager.seek(position);
    LogService.verbose('AudioService', 'Seek → ${_fmtDur(position)}');
  }

  // ── Tape Scrub helpers ─────────────────────────────────────────────────────
  //
  // Digunakan oleh PlayerProgressSection selama scrub agar speed berubah
  // sementara tanpa menulis ke SharedPreferences.
  // Panggil [clearScrubSpeed] saat scrub selesai untuk memulihkan.

  /// Ubah kecepatan sementara selama scrub (tidak disimpan ke prefs).
  static Future<void> setTemporaryScrubSpeed(double speed) =>
      PlaybackManager.setSpeed(speed.clamp(0.25, 3.0));

  /// Pulihkan kecepatan ke nilai yang tersimpan user.
  static Future<void> clearScrubSpeed() =>
      PlaybackManager.setSpeed(AudioEffectsService.playbackSpeed.value);

  static Future<void> skipNext() async {
    initialize();
    await PlaybackManager.skipNext();
    LogService.log('AudioService', 'Skip → next');
  }

  static Future<void> skipPrevious() async {
    initialize();
    await PlaybackManager.skipPrevious();
    LogService.log('AudioService', 'Skip → previous');
  }

  /// Jump to any item in the current queue without reloading the queue.
  static Future<void> playFromCurrentQueue(int index) async {
    if (index < 0 || index >= _playlist.length) return;
    _currentIndex = index;
    final song    = _playlist[index];
    _setState(playbackState.value.copyWith(
      currentSong:  song,
      currentIndex: index,
    ));
    await PlaybackManager.setTrack(index);
    await PlaybackManager.play();
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
    await PlaybackManager.setRepeatMode(next.name);
    LogService.log('AudioService', 'Loop mode → ${next.name}');
  }

  static Future<void> toggleShuffle() async {
    initialize();
    final current = playbackState.value.shuffleEnabled;
    final next    = !current;
    // Optimistic UI update — native confirms via shuffleModeStream.
    _setState(playbackState.value.copyWith(shuffleEnabled: next));
    await PlaybackManager.setShuffleMode(next);
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
    unawaited(PlaybackManager.insertNext(song));
    LogService.log('AudioService', 'Queued next: "${song.title}"');
  }

  /// Append [song] at the end of the queue.
  static void addToQueue(LocalSong song) {
    if (_playlist.isNotEmpty) {
      final mutable = List<LocalSong>.from(_playlist)..add(song);
      _playlist     = List<LocalSong>.unmodifiable(mutable);
      _setState(playbackState.value.copyWith(currentPlaylist: _playlist));
    }
    unawaited(PlaybackManager.appendToQueue(song));
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

    unawaited(PlaybackManager.reorderQueue(oldIndex, adjustedNew));
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

  // ── ReplayGain ───────────────────────────────────────────────────────────[...]

  /// ARCH-01 fix: accepts [prevSong] to avoid reading the already-overwritten
  /// [_previousSong] static field from inside an async call. Callers that have
  /// already advanced [_previousSong] should pass the captured predecessor here.
  /// Callers that haven't yet overwritten [_previousSong] can omit this param.
  ///
  /// Fail-open contract: ReplayGain is a purely cosmetic loudness adjustment.
  /// Every native call inside is already guarded by
  /// [PlaybackManager]'s `_dspGuard` and cannot throw, but this method also
  /// wraps its entire body in a try/catch as a second line of defense — a
  /// resolver I/O error or any other unexpected failure here must never
  /// propagate to [playSongAt], which would otherwise skip
  /// `PlaybackManager.play()` entirely (see playSongAt's regression history).
  static Future<void> _applyReplayGain(LocalSong song, {LocalSong? prevSong}) async {
    try {
      final mode = AudioEffectsService.replayGainMode.value;
      if (mode == ReplayGainMode.off) {
        // Bypass the native DSP slot — audio passes through unmodified.
        PlaybackManager.setNativeReplayGainBypass(true);
        return;
      }

      // If native loudness normalisation is active it serves as the dynamic
      // gain authority.  Applying both would cause the EBU R128 loop to
      // continuously re-normalise an already ReplayGain-adjusted signal,
      // producing an unstable, oscillating gain.  In this case, only the
      // user's ReplayGain preamp offset (if non-zero) is forwarded so the
      // normaliser sees the user's intentional level preference.
      if (AudioEffectsService.loudnessNormEnabled.value) {
        final preamp = AudioEffectsService.replayGainPreamp.value;
        if (preamp != 0.0) {
          PlaybackManager.setNativeReplayGain(
            gainDb: preamp,
            peakLinear: 0.0,
            useClippingProtection: false,
          );
          PlaybackManager.setNativeReplayGainBypass(false);
        } else {
          PlaybackManager.setNativeReplayGainBypass(true);
        }
        LogService.verbose(
          'AudioService',
          'ReplayGain deferred to Loudness Norm'
          ' (preamp: ${preamp.toStringAsFixed(1)} dB)',
        );
        return;
      }

      final data = await LoudnessSourceResolver.resolve(
        song:         song,
        mode:         mode,
        previousSong: prevSong ?? _previousSong,
      );
      if (!data.hasData) {
        // No metadata found — bypass so audio is not silently attenuated.
        PlaybackManager.setNativeReplayGainBypass(true);
        LogService.verbose('AudioService', 'No ReplayGain metadata for "${song.title}" — bypass');
        return;
      }

      final preamp  = AudioEffectsService.replayGainPreamp.value;
      final useClip = AudioEffectsService.clippingProtection.value;
      // Pass raw gain + preamp to native so the C layer handles dB→linear
      // conversion and optional clipping protection in one atomic step.
      // Clamped to [−24, +24] dB in the C processor — no Dart-side clamping needed.
      final gainDb     = data.gainDb + preamp;
      final peakLinear = data.peakLinear ?? 0.0;

      PlaybackManager.setNativeReplayGain(
        gainDb: gainDb,
        peakLinear: peakLinear,
        useClippingProtection: useClip,
      );
      PlaybackManager.setNativeReplayGainBypass(false);

      LogService.verbose(
        'AudioService',
        'ReplayGain "${song.title}": ${gainDb.toStringAsFixed(2)} dB '
        '(peak=${peakLinear > 0 ? peakLinear.toStringAsFixed(3) : "n/a"}, '
        'clip=$useClip, src=${data.source.label})',
      );
    } catch (e, st) {
      // Fail-open: never let a ReplayGain failure block playback.
      LogService.error(
        'AudioService',
        'ReplayGain skipped (fail-open): $e',
        stackTrace: st.toString(),
      );
    }
  }

  // ── State sync (app resume) ───────────────────────────────────────────────

  /// Re-sync Dart state dari engine yang sedang aktif.
  /// Call after initialize() dan pada setiap AppLifecycleState.resumed.
  /// 
  /// STARTUP FIX: All async operations wrapped with timeouts to prevent
  /// indefinite hang if native layer is not responding.
  /// - getPlaybackSnapshot: 5s timeout
  /// - artwork prewarm: 2s timeout  
  /// - replay gain apply: 2s timeout
  /// Timeouts are non-fatal; execution continues and logs the event.
  static Future<void> syncFromNative() async {
    if (kIsWeb) return;

    try {
      // ── STARTUP FIX: Wrap getPlaybackSnapshot with 5s timeout ──────────────
      final snapshot = await PlaybackManager.getPlaybackSnapshot()
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              LogService.warn(
                'AudioService',
                'syncFromNative: getPlaybackSnapshot() timeout (5s) — native layer may be slow or unresponsive',
              );
              return null;
            },
          );
      
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
      final song = songs[index];

      final miniPx = ArtworkRepository.instance.resolveTargetPx(46.3);

      // ── STARTUP FIX: Wrap artwork prewarm with 2s timeout ───────────────
      try {
        await ArtworkRepository.instance.prewarmImageCache(
          [song.id],
          targetSizePx: miniPx,
        ).timeout(
          const Duration(seconds: 2),
          onTimeout: () {
            LogService.verbose(
              'AudioService',
              'syncFromNative: artwork prewarm timeout (2s) — skipping',
            );
            return;
          },
        );
      } catch (e) {
        LogService.verbose('AudioService', 'syncFromNative: artwork prewarm error: $e');
      }

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

      // ── STARTUP FIX: Wrap replay gain apply with 2s timeout ──────────────
      try {
        await _applyReplayGain(song).timeout(
          const Duration(seconds: 2),
          onTimeout: () {
            LogService.verbose(
              'AudioService',
              'syncFromNative: replay gain apply timeout (2s) — skipping',
            );
            return;
          },
        );
      } catch (e) {
        LogService.verbose('AudioService', 'syncFromNative: replay gain apply error: $e');
      }
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
