import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/local_song.dart';
import 'audio/audio_engine.dart';
import 'audio/audio_effects_service.dart';
import 'audio/crossfade_controller.dart';
import 'audio_playback_state.dart';
import 'audio_source_builder.dart';
import 'history_service.dart';
import 'log_service.dart';

/// Main facade for all audio playback operations.
///
/// Internally delegates to [AudioEngine] for the player instance
/// and [CrossfadeController] for crossfade behaviour.
class AudioService {
  AudioService._();

  // Expose the engine's player so legacy code continues to compile.
  static AudioPlayer get player => AudioEngine.player;

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
          _onTrackCompleted();
        }
      }),
    );

    _subscriptions.add(
      p.durationStream.listen((Duration? duration) {
        _setState(playbackState.value.copyWith(
          duration: duration ?? Duration.zero,
        ));
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

        LogService.log('AudioService', 'Playing: ${playlist[index].title}');
        unawaited(HistoryService.trackPlay(playlist[index]));
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
      _setState(playbackState.value.copyWith(
        speed: AudioEffectsService.playbackSpeed.value,
      ));
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

    if (_isLoading) return;
    if (playlist.isEmpty || index < 0 || index >= playlist.length) return;

    _isLoading = true;
    final immutablePlaylist = List<LocalSong>.unmodifiable(playlist);
    final selectedSong = immutablePlaylist[index];

    _setState(playbackState.value.copyWith(
      currentSong: selectedSong,
      currentIndex: index,
      currentPlaylist: immutablePlaylist,
      isLoading: true,
    ));

    try {
      _queue = ConcatenatingAudioSource(
        useLazyPreparation: true,
        shuffleOrder: DefaultShuffleOrder(),
        children: immutablePlaylist.map(buildAudioSource).toList(),
      );

      await player.setAudioSource(_queue!, initialIndex: index);

      if (autoplay) await player.play();
    } catch (e, st) {
      LogService.error('AudioService', 'playSongAt error: $e\n$st');
    } finally {
      _isLoading = false;
      _setState(playbackState.value.copyWith(isLoading: false));
      _syncPlaybackState();
    }
  }

  static Future<void> play() async {
    initialize();
    await player.play();
    _syncPlaybackState();
  }

  static Future<void> pause() async {
    initialize();
    await player.pause();
    _syncPlaybackState();
  }

  static Future<void> seek(Duration position) async {
    initialize();
    await player.seek(position);
    _syncPlaybackState();
  }

  static Future<void> skipNext() async {
    // If crossfade is active, let the controller handle transition.
    // Otherwise, just seek to next.
    if (!player.hasNext) return;
    await player.seekToNext();
    LogService.log('AudioService', 'Skip next');
  }

  static Future<void> skipPrevious() async {
    // Restart track if past 3 seconds, else go to previous.
    if (player.position.inSeconds > 3) {
      await player.seek(Duration.zero);
    } else {
      await player.seekToPrevious();
    }
    LogService.log('AudioService', 'Skip previous');
  }

  static Future<void> playFromCurrentQueue(int index) async {
    await player.seek(Duration.zero, index: index);
    if (!player.playing) await player.play();
  }

  // ── Loop / Shuffle ─────────────────────────────────────────────────────────

  static Future<void> cycleLoopMode() async {
    final next = switch (loopMode) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    await player.setLoopMode(next);
    LogService.log('AudioService', 'Loop: $next');
  }

  static Future<void> toggleShuffle() async {
    final enabled = !shuffleEnabled;
    await player.setShuffleModeEnabled(enabled);
    if (enabled) await player.shuffle();
    LogService.log('AudioService', 'Shuffle: $enabled');
  }

  // ── Queue management ───────────────────────────────────────────────────────

  static void addToQueueNext(LocalSong song) {
    if (_queue == null) return;
    final nextIndex = (currentIndex + 1).clamp(0, _queue!.length);
    _queue!.insert(nextIndex, buildAudioSource(song));
    final newPlaylist = List<LocalSong>.from(currentPlaylist)
      ..insert(nextIndex, song);
    _setState(playbackState.value.copyWith(
      currentPlaylist: List<LocalSong>.unmodifiable(newPlaylist),
    ));
    LogService.log('AudioService', 'Queued next: ${song.title}');
  }

  static void addToQueue(LocalSong song) {
    if (_queue == null) return;
    _queue!.add(buildAudioSource(song));
    final newPlaylist = List<LocalSong>.from(currentPlaylist)..add(song);
    _setState(playbackState.value.copyWith(
      currentPlaylist: List<LocalSong>.unmodifiable(newPlaylist),
    ));
    LogService.log('AudioService', 'Queued end: ${song.title}');
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  static void _onTrackCompleted() {
    final state = playbackState.value;
    if (_isLoading) return;

    if (state.loopMode == LoopMode.one) {
      player.seek(Duration.zero).then((_) => player.play());
      return;
    }

    if (state.currentIndex >= state.currentPlaylist.length - 1) {
      if (state.loopMode == LoopMode.all) {
        player.seek(Duration.zero, index: 0).then((_) => player.play());
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

  static Future<void> dispose() async {
    CrossfadeController.dispose();
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    _initialized = false;
    await AudioEngine.dispose();
  }
}
