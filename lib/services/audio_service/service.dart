part of '../audio_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  AudioService — High-Level Playback Facade (Dual-Player Architecture)
// ─────────────────────────────────────────────────────────────────────────────
//
//  Queue management is fully manual (no ConcatenatingAudioSource) so that
//  the dual-player engine can do true gapless swaps and real crossfades.
//
//  Gapless flow:
//    positionStream → _onPosition() → preload next track on standby player
//    Track completes → if standby is ready: instant _gaplessSwap()
//                      otherwise:           _loadAndPlay() on active
//
//  Crossfade flow (delegated to CrossfadeController):
//    CrossfadeController.triggerNow(nextIndex) or auto-timer trigger.
//    On complete: CrossfadeController calls _onHandoffComplete(newIndex).
//
// ─────────────────────────────────────────────────────────────────────────────

class AudioService {
  AudioService._();

  // ── Public state ──────────────────────────────────────────────────────────

  static final ValueNotifier<AudioPlaybackState> playbackState =
      ValueNotifier<AudioPlaybackState>(const AudioPlaybackState());

  static AudioPlayer get player => AudioEngine.activePlayer;

  // ── Queue state ────────────────────────────────────────────────────────────

  static List<LocalSong> _playlist   = const [];
  static int             _curIndex   = 0;
  static LoopMode        _loopMode   = LoopMode.off;
  static bool            _shuffled   = false;
  static List<int>       _shuffleOrd = [];

  // ── Preload state ─────────────────────────────────────────────────────────

  static int?  _preloadedIdx;
  static bool  _isPreloading = false;

  // ── Guards ────────────────────────────────────────────────────────────────

  static bool _isLoading   = false;
  static bool _initialized = false;

  // ── Subscriptions ─────────────────────────────────────────────────────────

  static final List<StreamSubscription<dynamic>> _playerSubs = [];
  static VoidCallback? _speedListener;

  // ── Convenience getters ────────────────────────────────────────────────────

  static LocalSong?      get currentSong     => playbackState.value.currentSong;
  static bool            get isPlaying       => playbackState.value.isPlaying;
  static int             get currentIndex    => playbackState.value.currentIndex;
  static List<LocalSong> get currentPlaylist => playbackState.value.currentPlaylist;
  static LoopMode        get loopMode        => playbackState.value.loopMode;
  static bool            get shuffleEnabled  => playbackState.value.shuffleEnabled;

  // ── Initialization ────────────────────────────────────────────────────────

  static void initialize() {
    if (_initialized) return;
    _initialized = true;

    CrossfadeController.initialize(
      getNextIndex:      _nextIdx,
      getSong:           (i) => (i >= 0 && i < _playlist.length) ? _playlist[i] : null,
      onHandoffComplete: _onHandoffComplete,
    );

    _speedListener = () {
      _setState(playbackState.value.copyWith(
        speed: AudioEffectsService.playbackSpeed.value,
      ));
    };
    AudioEffectsService.playbackSpeed.addListener(_speedListener!);

    LogService.log('AudioService', 'Initialized (dual-player)');
  }

  // ── Primary playback ──────────────────────────────────────────────────────

  static Future<void> playSongAt({
    required List<LocalSong> playlist,
    required int index,
    bool autoplay = true,
  }) async {
    initialize();
    if (_isLoading) return;
    if (playlist.isEmpty || index < 0 || index >= playlist.length) return;

    _isLoading = true;
    CrossfadeController.cancel();
    await _resetStandby();

    _playlist     = List<LocalSong>.unmodifiable(playlist);
    _curIndex     = index;
    _preloadedIdx = null;
    _isPreloading = false;

    if (_shuffled) {
      _shuffleOrd = _buildShuffleOrder(_playlist.length, _curIndex);
    }

    final song = _playlist[_curIndex];
    _setState(playbackState.value.copyWith(
      currentSong:     song,
      currentIndex:    _curIndex,
      currentPlaylist: _playlist,
      isLoading:       true,
      loopMode:        _loopMode,
      shuffleEnabled:  _shuffled,
    ));

    try {
      await AudioEngine.activePlayer.setAudioSource(buildAudioSource(song));
      if (autoplay) await AudioEngine.activePlayer.play();

      _resubscribeToActivePlayer();
      AudioEffectsService.reapplyToActivePlayer();

      LoudnessAnalyzer.analyzeInBackground(
        playlist.where((s) => s.path.isNotEmpty).map((s) => s.path).toList(),
      );

      if (AudioEffectsService.audioNormalize.value) {
        unawaited(_applyLufsToActive(song));
      }

      unawaited(HistoryService.trackPlay(song));
      LogService.log('AudioService', 'Playing: ${song.title}',
          extra: {'index': index, 'total': playlist.length});
    } catch (e, st) {
      LogService.error('AudioService', 'playSongAt: $e', stackTrace: st);
    } finally {
      _isLoading = false;
      _setState(playbackState.value.copyWith(isLoading: false));
    }
  }

  // ── Transport ─────────────────────────────────────────────────────────────

  static Future<void> play() async {
    initialize();
    await AudioEngine.activePlayer.play();
    _syncState();
  }

  static Future<void> pause() async {
    initialize();
    await AudioEngine.activePlayer.pause();
    _syncState();
  }

  static Future<void> seek(Duration position) async {
    initialize();
    await AudioEngine.activePlayer.seek(position);
    _syncState();
  }

  static Future<void> skipNext() async {
    initialize();
    final nextIdx = _nextIdx();
    if (nextIdx == null) return;

    if (AudioEffectsService.crossfadeDuration.value > 0) {
      await CrossfadeController.triggerNow(nextIdx);
    } else if (_preloadedIdx == nextIdx) {
      await _gaplessSwap(nextIdx);
    } else {
      await _loadAndPlay(nextIdx);
    }
    LogService.log('AudioService', 'Skip next → $nextIdx');
  }

  static Future<void> skipPrevious() async {
    initialize();
    if (AudioEngine.activePlayer.position.inSeconds > 3) {
      await AudioEngine.activePlayer.seek(Duration.zero);
    } else {
      final prevIdx = _prevIdx();
      if (prevIdx != null) {
        if (AudioEffectsService.crossfadeDuration.value > 0) {
          await CrossfadeController.triggerNow(prevIdx);
        } else {
          await _loadAndPlay(prevIdx);
        }
      }
    }
    LogService.log('AudioService', 'Skip previous');
  }

  static Future<void> playFromCurrentQueue(int index) async {
    initialize();
    if (index < 0 || index >= _playlist.length) return;
    if (index == _curIndex) {
      if (!AudioEngine.activePlayer.playing) await AudioEngine.activePlayer.play();
      return;
    }
    if (AudioEffectsService.crossfadeDuration.value > 0) {
      await CrossfadeController.triggerNow(index);
    } else if (_preloadedIdx == index) {
      await _gaplessSwap(index);
    } else {
      await _loadAndPlay(index);
    }
  }

  // ── Loop / Shuffle ────────────────────────────────────────────────────────

  static Future<void> cycleLoopMode() async {
    initialize();
    _loopMode = switch (_loopMode) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    _setState(playbackState.value.copyWith(loopMode: _loopMode));
    LogService.log('AudioService', 'Loop: $_loopMode');
  }

  static Future<void> toggleShuffle() async {
    initialize();
    _shuffled = !_shuffled;
    if (_shuffled) {
      _shuffleOrd = _buildShuffleOrder(_playlist.length, _curIndex);
    } else {
      _shuffleOrd = [];
    }
    _setState(playbackState.value.copyWith(shuffleEnabled: _shuffled));
    LogService.log('AudioService', 'Shuffle: $_shuffled');
  }

  // ── Queue management ──────────────────────────────────────────────────────

  static void addToQueueNext(LocalSong song) {
    initialize();
    if (_playlist.isEmpty) return;
    final insertAt = (_curIndex + 1).clamp(0, _playlist.length);
    final newList  = List<LocalSong>.from(_playlist)..insert(insertAt, song);
    _playlist = List<LocalSong>.unmodifiable(newList);

    if (_shuffled && _shuffleOrd.isNotEmpty) {
      for (var i = 0; i < _shuffleOrd.length; i++) {
        if (_shuffleOrd[i] >= insertAt) _shuffleOrd[i]++;
      }
      final curPos = _shuffleOrd.indexOf(_curIndex);
      _shuffleOrd.insert(curPos + 1, insertAt);
    }
    if (_preloadedIdx != null && _preloadedIdx! >= insertAt) {
      _preloadedIdx = _preloadedIdx! + 1;
    }
    _setState(playbackState.value.copyWith(currentPlaylist: _playlist));
    LogService.log('AudioService', 'Queued next: ${song.title}');
  }

  static void addToQueue(LocalSong song) {
    initialize();
    if (_playlist.isEmpty) return;
    final newList = List<LocalSong>.from(_playlist)..add(song);
    _playlist = List<LocalSong>.unmodifiable(newList);
    if (_shuffled && _shuffleOrd.isNotEmpty) {
      _shuffleOrd.add(newList.length - 1);
    }
    _setState(playbackState.value.copyWith(currentPlaylist: _playlist));
    LogService.log('AudioService', 'Queued end: ${song.title}');
  }

  // ── Internal – load helpers ───────────────────────────────────────────────

  static Future<void> _loadAndPlay(int index) async {
    if (_isLoading) return;
    _isLoading    = true;
    _preloadedIdx = null;

    final song = _playlist[index];
    _curIndex   = index;
    _setState(playbackState.value.copyWith(
      currentIndex: index,
      currentSong:  song,
      isLoading:    true,
    ));

    try {
      await AudioEngine.activePlayer.setAudioSource(buildAudioSource(song));
      await AudioEngine.activePlayer.play();

      _resubscribeToActivePlayer();
      AudioEffectsService.reapplyToActivePlayer();

      if (AudioEffectsService.audioNormalize.value) {
        unawaited(_applyLufsToActive(song));
      }
      unawaited(HistoryService.trackPlay(song));
      LogService.debug('AudioService', 'Load & play: ${song.title}');
    } catch (e) {
      LogService.error('AudioService', '_loadAndPlay: $e');
    } finally {
      _isLoading = false;
      _setState(playbackState.value.copyWith(isLoading: false));
    }
  }

  static Future<void> _gaplessSwap(int nextIdx) async {
    LogService.debug('AudioService', 'Gapless swap → $nextIdx');

    AudioEngine.standbySlot.setVolume(1.0);
    try { await AudioEngine.standbyPlayer.play(); } catch (_) {}

    AudioEngine.handoff();

    try {
      await AudioEngine.standbyPlayer.stop();
      AudioEngine.standbySlot.setVolume(1.0);
    } catch (_) {}

    _curIndex     = nextIdx;
    _preloadedIdx = null;
    final song    = _playlist[nextIdx];

    _setState(playbackState.value.copyWith(
      currentIndex: nextIdx,
      currentSong:  song,
    ));

    _resubscribeToActivePlayer();
    AudioEffectsService.reapplyToActivePlayer();
    unawaited(HistoryService.trackPlay(song));
    LogService.log('AudioService', 'Gapless: ${song.title}');
  }

  static Future<void> _preloadNext() async {
    if (_isPreloading || _preloadedIdx != null) return;
    final nextIdx = _nextIdx();
    if (nextIdx == null) return;

    _isPreloading = true;
    try {
      final song = _playlist[nextIdx];
      AudioEngine.standbySlot.setVolume(0.0);
      await AudioEngine.standbyPlayer.setAudioSource(buildAudioSource(song));
      _preloadedIdx = nextIdx;
      LogService.verbose('AudioService', 'Preloaded: ${song.title}',
          extra: {'index': nextIdx});

      if (AudioEffectsService.audioNormalize.value) {
        unawaited(_applyLufsToStandby(song));
      }
    } catch (e) {
      LogService.warn('AudioService', 'Preload failed: $e');
      _preloadedIdx = null;
    } finally {
      _isPreloading = false;
    }
  }

  static Future<void> _resetStandby() async {
    try {
      await AudioEngine.standbyPlayer.stop();
      AudioEngine.standbySlot.setVolume(1.0);
    } catch (_) {}
  }

  // ── Internal – handoff callback ───────────────────────────────────────────

  static void _onHandoffComplete(int newIndex) {
    _curIndex     = newIndex;
    _preloadedIdx = null;

    final song = (newIndex >= 0 && newIndex < _playlist.length)
        ? _playlist[newIndex]
        : null;

    _setState(playbackState.value.copyWith(
      currentIndex: newIndex,
      currentSong:  song,
    ));

    _resubscribeToActivePlayer();
    AudioEffectsService.reapplyToActivePlayer();

    if (song != null) unawaited(HistoryService.trackPlay(song));
    LogService.log('AudioService', 'Handoff done: ${song?.title}');
  }

  // ── Internal – player subscriptions ──────────────────────────────────────

  static void _resubscribeToActivePlayer() {
    for (final s in _playerSubs) s.cancel();
    _playerSubs.clear();

    final p = AudioEngine.activePlayer;

    _playerSubs.add(p.playerStateStream.listen((state) {
      _setState(playbackState.value.copyWith(
        isPlaying:       state.playing,
        processingState: state.processingState,
      ));
      if (state.processingState == ProcessingState.completed) {
        _onTrackCompleted();
      }
    }));

    _playerSubs.add(p.durationStream.listen((dur) {
      _setState(playbackState.value.copyWith(duration: dur ?? Duration.zero));
    }));

    _playerSubs.add(p.positionStream.listen(_onPosition));
  }

  static void _onPosition(Duration position) {
    final duration = playbackState.value.duration;
    if (duration == Duration.zero) return;
    final remaining = duration - position;
    if (remaining <= Duration.zero) return;

    final crossSec      = AudioEffectsService.crossfadeDuration.value;
    final preloadBuffer = Duration(seconds: (crossSec + 12).ceil());

    if (remaining <= preloadBuffer && _preloadedIdx == null && !_isPreloading) {
      unawaited(_preloadNext());
    }
  }

  // ── Internal – track completion ───────────────────────────────────────────

  static void _onTrackCompleted() {
    if (_isLoading) return;

    // Notify sleep timer (for end-of-song mode)
    SleepTimerService.onSongEnded();

    if (_loopMode == LoopMode.one) {
      AudioEngine.activePlayer
          .seek(Duration.zero)
          .then((_) => AudioEngine.activePlayer.play());
      return;
    }

    final nextIdx = _nextIdx();
    if (nextIdx == null) {
      _setState(playbackState.value.copyWith(isPlaying: false));
      LogService.debug('AudioService', 'Queue ended');
      return;
    }

    if (_preloadedIdx == nextIdx) {
      unawaited(_gaplessSwap(nextIdx));
    } else {
      unawaited(_loadAndPlay(nextIdx));
    }
  }

  // ── Internal – index helpers ──────────────────────────────────────────────

  static int? _nextIdx() {
    if (_playlist.isEmpty) return null;
    if (_loopMode == LoopMode.one) return _curIndex;

    if (_shuffled && _shuffleOrd.isNotEmpty) {
      final pos = _shuffleOrd.indexOf(_curIndex);
      if (pos < 0) return null;
      final next = pos + 1;
      if (next >= _shuffleOrd.length) {
        return _loopMode == LoopMode.all ? _shuffleOrd[0] : null;
      }
      return _shuffleOrd[next];
    }

    final next = _curIndex + 1;
    if (next >= _playlist.length) {
      return _loopMode == LoopMode.all ? 0 : null;
    }
    return next;
  }

  static int? _prevIdx() {
    if (_playlist.isEmpty) return null;

    if (_shuffled && _shuffleOrd.isNotEmpty) {
      final pos = _shuffleOrd.indexOf(_curIndex);
      if (pos < 0) return null;
      final prev = pos - 1;
      if (prev < 0) {
        return _loopMode == LoopMode.all ? _shuffleOrd.last : null;
      }
      return _shuffleOrd[prev];
    }

    final prev = _curIndex - 1;
    if (prev < 0) {
      return _loopMode == LoopMode.all ? _playlist.length - 1 : null;
    }
    return prev;
  }

  static List<int> _buildShuffleOrder(int length, int currentIndex) {
    if (length == 0) return [];
    final rest = List<int>.generate(length, (i) => i)
      ..remove(currentIndex)
      ..shuffle();
    return [currentIndex, ...rest];
  }

  // ── Internal – loudness normalization ─────────────────────────────────────

  static Future<void> _applyLufsToActive(LocalSong song) async {
    if (!AudioEffectsService.audioNormalize.value) return;
    try {
      final result = await LoudnessAnalyzer.analyze(song.path);
      AudioEngine.applyNormalizeToSlot(
        AudioEngine.activeSlot,
        enabled:      true,
        targetGainMb: result?.recommendedGainMb ?? 0.0,
      );
      LogService.verbose('AudioService', 'LUFS active: ${result?.lufs.toStringAsFixed(1)} dB');
    } catch (_) {}
  }

  static Future<void> _applyLufsToStandby(LocalSong song) async {
    if (!AudioEffectsService.audioNormalize.value) return;
    try {
      final result = await LoudnessAnalyzer.analyze(song.path);
      AudioEngine.applyNormalizeToSlot(
        AudioEngine.standbySlot,
        enabled:      true,
        targetGainMb: result?.recommendedGainMb ?? 0.0,
      );
      LogService.verbose('AudioService', 'LUFS standby: ${result?.lufs.toStringAsFixed(1)} dB');
    } catch (_) {}
  }

  // ── Internal – state ──────────────────────────────────────────────────────

  static void _setState(AudioPlaybackState state) => playbackState.value = state;

  static void _syncState() {
    _setState(playbackState.value.copyWith(
      isPlaying:       AudioEngine.activePlayer.playing,
      processingState: AudioEngine.activePlayer.processingState,
    ));
  }

  // ── Dispose ───────────────────────────────────────────────────────────────

  static Future<void> dispose() async {
    CrossfadeController.dispose();
    for (final s in _playerSubs) s.cancel();
    _playerSubs.clear();
    if (_speedListener != null) {
      AudioEffectsService.playbackSpeed.removeListener(_speedListener!);
      _speedListener = null;
    }
    _initialized  = false;
    _isLoading    = false;
    _isPreloading = false;
    _preloadedIdx = null;
    await AudioEngine.dispose();
  }
}
