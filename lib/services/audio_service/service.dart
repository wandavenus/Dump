part of '../audio_service.dart';

/// Main facade for all audio playback operations.
///
/// Internally delegates to [AudioEngine] for the player instance
/// and [CrossfadeController] for crossfade behaviour.
class AudioService {
  AudioService._();

  // Expose the engine's player so legacy code continues to compile.
  static AudioPlayer get player => AudioEngine.player;

  // ignore: deprecated_member_use
  static ConcatenatingAudioSource? _queue;
  static final ValueNotifier<AudioPlaybackState> playbackState =
      ValueNotifier<AudioPlaybackState>(const AudioPlaybackState());

  static bool _initialized = false;
  static bool _isLoading = false;
  static final List<StreamSubscription<dynamic>> _subscriptions = [];

  // ── Convenience getters ────────────────────────────────────────────────────

  static LocalSong? get currentSong => playbackState.value.currentSong;
  static bool get isPlaying => playbackState.value.isPlaying;
  static int get currentIndex => playbackState.value.currentIndex;
  static List<LocalSong> get currentPlaylist =>
      playbackState.value.currentPlaylist;
  static LoopMode get loopMode => playbackState.value.loopMode;
  static bool get shuffleEnabled => playbackState.value.shuffleEnabled;

  // ── Init ───────────────────────────────────────────────────────────────────

  static void initialize() {
    if (_initialized) return;
    _initialized = true;

    final p = player;

    _subscriptions.add(
      p.playerStateStream.listen((PlayerState state) {
        _setState(playbackState.value.copyWith(
          isPlaying: state.playing,
          processingState: state.processingState,
        ));

        if (state.processingState == ProcessingState.completed) {
          LogService.verbose('AudioService', 'Track completed → advancing');
          _onTrackCompleted();
        }
      }),
    );

    _subscriptions.add(
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

    _subscriptions.add(
      p.currentIndexStream.listen((index) {
        if (index == null) return;
        final playlist = playbackState.value.currentPlaylist;
        if (index < 0 || index >= playlist.length) return;

        _setState(playbackState.value.copyWith(
          currentIndex: index,
          currentSong: playlist[index],
        ));

        final song = playlist[index];
        LogService.log(
          'AudioService',
          'Now playing [${index + 1}/${playlist.length}]: '
          '"${song.title}" — ${song.artist}',
        );
        unawaited(HistoryService.trackPlay(song));
      }),
    );

    _subscriptions.add(
      p.loopModeStream.listen((mode) {
        _setState(playbackState.value.copyWith(loopMode: mode));
      }),
    );

    _subscriptions.add(
      p.shuffleModeEnabledStream.listen((enabled) {
        _setState(playbackState.value.copyWith(shuffleEnabled: enabled));
      }),
    );

    AudioEffectsService.playbackSpeed.addListener(() {
      final spd = AudioEffectsService.playbackSpeed.value;
      _setState(playbackState.value.copyWith(speed: spd));
      LogService.verbose('AudioService', 'Speed changed: ${spd.toStringAsFixed(2)}x');
    });

    CrossfadeController.initialize();
    _syncPlaybackState();
    LogService.log('AudioService', 'Initialized');
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
    final immutablePlaylist = List<LocalSong>.unmodifiable(playlist);
    final selectedSong = immutablePlaylist[index];

    LogService.log(
      'AudioService',
      'Loading "${selectedSong.title}" — ${selectedSong.artist} '
      '(track ${index + 1}/${playlist.length})',
    );

    _setState(playbackState.value.copyWith(
      currentSong: selectedSong,
      currentIndex: index,
      currentPlaylist: immutablePlaylist,
      isLoading: true,
    ));

    try {
      // ignore: deprecated_member_use
      _queue = ConcatenatingAudioSource(
        useLazyPreparation: true,
        shuffleOrder: DefaultShuffleOrder(),
        children: immutablePlaylist.map(buildAudioSource).toList(),
      );

      await player.setAudioSource(_queue!, initialIndex: index);
      LogService.verbose('AudioService',
          'AudioSource set — ${immutablePlaylist.length} tracks in queue');

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
    if (!player.hasNext) {
      LogService.verbose('AudioService', 'skipNext: already at end of queue');
      return;
    }
    await player.seekToNext();
    LogService.log('AudioService', 'Skip → next track');
  }

  static Future<void> skipPrevious() async {
    if (player.position.inSeconds > 3) {
      await player.seek(Duration.zero);
      LogService.verbose('AudioService', 'Skip previous: restarted track');
    } else {
      await player.seekToPrevious();
      LogService.log('AudioService', 'Skip → previous track');
    }
  }

  static Future<void> playFromCurrentQueue(int index) async {
    final song = currentPlaylist.elementAtOrNull(index);
    await player.seek(Duration.zero, index: index);
    if (!player.playing) await player.play();
    if (song != null) {
      LogService.log('AudioService',
          'Queue jump → [${index + 1}]: "${song.title}"');
    }
  }

  // ── Loop / Shuffle ─────────────────────────────────────────────────────────

  static Future<void> cycleLoopMode() async {
    final next = switch (loopMode) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    await player.setLoopMode(next);
    LogService.log('AudioService', 'Loop mode → ${next.name}');
  }

  static Future<void> toggleShuffle() async {
    final enabled = !shuffleEnabled;
    await player.setShuffleModeEnabled(enabled);
    if (enabled) await player.shuffle();
    LogService.log('AudioService', 'Shuffle → ${enabled ? 'on' : 'off'}');
  }

  // ── Queue management ───────────────────────────────────────────────────────

  static void addToQueueNext(LocalSong song) {
    if (_queue == null) return;
    final nextIndex = (currentIndex + 1).clamp(0, _queue!.length).toInt();
    _queue!.insert(nextIndex, buildAudioSource(song));
    final newPlaylist = List<LocalSong>.from(currentPlaylist)
      ..insert(nextIndex, song);
    _setState(playbackState.value.copyWith(
      currentPlaylist: List<LocalSong>.unmodifiable(newPlaylist),
    ));
    LogService.log('AudioService',
        'Queued next: "${song.title}" at position ${nextIndex + 1}');
  }

  static void addToQueue(LocalSong song) {
    if (_queue == null) return;
    _queue!.add(buildAudioSource(song));
    final newPlaylist = List<LocalSong>.from(currentPlaylist)..add(song);
    _setState(playbackState.value.copyWith(
      currentPlaylist: List<LocalSong>.unmodifiable(newPlaylist),
    ));
    LogService.log('AudioService',
        'Queued at end: "${song.title}" (queue size: ${newPlaylist.length})');
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  static void _onTrackCompleted() {
    final state = playbackState.value;
    if (_isLoading) return;

    if (state.loopMode == LoopMode.one) {
      player.seek(Duration.zero).then((_) => player.play());
      LogService.verbose('AudioService', 'Loop one: restarting track');
      return;
    }

    if (state.currentIndex >= state.currentPlaylist.length - 1) {
      if (state.loopMode == LoopMode.all) {
        player.seek(Duration.zero, index: 0).then((_) => player.play());
        LogService.verbose('AudioService', 'Loop all: wrapping to track 1');
      } else {
        LogService.verbose('AudioService', 'End of queue reached');
      }
      return;
    }

    skipNext();
  }

  static void _syncPlaybackState() {
    _setState(playbackState.value.copyWith(
      isPlaying: player.playing,
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

  static Future<void> dispose() async {
    CrossfadeController.dispose();
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    _initialized = false;
    LogService.log('AudioService', 'Disposed');
    await AudioEngine.dispose();
  }
}
