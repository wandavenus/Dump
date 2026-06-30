import 'package:flutter/foundation.dart';

import '../models/local_song.dart';

enum ProcessingState { idle, loading, buffering, ready, completed }

enum LoopMode { off, all, one }

@immutable
class AudioPlaybackState {
  final LocalSong? currentSong;
  final bool isPlaying;
  final bool isLoading;
  final int currentIndex;
  final List<LocalSong> currentPlaylist;
  final ProcessingState processingState;
  final Duration duration;
  final Duration position;
  final LoopMode loopMode;
  final bool shuffleEnabled;
  final double speed;
  final bool sleepTimerActive;
  final int sleepTimerRemainingMs;

  /// The index of the next track ExoPlayer will actually play, as reported by
  /// native. Respects shuffle order and repeat mode.
  ///
  /// - `null`  → no native value received yet; callers fall back to linear math.
  /// - `-1`    → native confirms there is no next item (end of queue, repeat off).
  /// - `>= 0`  → the shuffle-correct next index into [currentPlaylist].
  ///
  /// Updated on every `currentTrack` EventChannel event, which native emits on
  /// track transitions, queue mutations, and full state snapshots.
  final int? nextTrackIndex;

  const AudioPlaybackState({
    this.currentSong,
    this.isPlaying = false,
    this.isLoading = false,
    this.currentIndex = 0,
    this.currentPlaylist = const [],
    this.processingState = ProcessingState.idle,
    this.duration = Duration.zero,
    this.position = Duration.zero,
    this.loopMode = LoopMode.off,
    this.shuffleEnabled = false,
    this.speed = 1.0,
    this.sleepTimerActive = false,
    this.sleepTimerRemainingMs = 0,
    this.nextTrackIndex,
  });

  AudioPlaybackState copyWith({
    LocalSong? currentSong,
    bool clearCurrentSong = false,
    bool? isPlaying,
    bool? isLoading,
    int? currentIndex,
    List<LocalSong>? currentPlaylist,
    ProcessingState? processingState,
    Duration? duration,
    Duration? position,
    LoopMode? loopMode,
    bool? shuffleEnabled,
    double? speed,
    bool? sleepTimerActive,
    int? sleepTimerRemainingMs,
    int? nextTrackIndex,
    bool clearNextTrackIndex = false,
  }) {
    return AudioPlaybackState(
      currentSong: clearCurrentSong ? null : currentSong ?? this.currentSong,
      isPlaying: isPlaying ?? this.isPlaying,
      isLoading: isLoading ?? this.isLoading,
      currentIndex: currentIndex ?? this.currentIndex,
      currentPlaylist: currentPlaylist ?? this.currentPlaylist,
      processingState: processingState ?? this.processingState,
      duration: duration ?? this.duration,
      position: position ?? this.position,
      loopMode: loopMode ?? this.loopMode,
      shuffleEnabled: shuffleEnabled ?? this.shuffleEnabled,
      speed: speed ?? this.speed,
      sleepTimerActive: sleepTimerActive ?? this.sleepTimerActive,
      sleepTimerRemainingMs:
          sleepTimerRemainingMs ?? this.sleepTimerRemainingMs,
      nextTrackIndex:
          clearNextTrackIndex ? null : nextTrackIndex ?? this.nextTrackIndex,
    );
  }
}
