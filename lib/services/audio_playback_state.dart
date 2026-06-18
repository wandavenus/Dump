import 'package:flutter/foundation.dart';
import 'audio/media3/media3_audio_player.dart';

import '../models/local_song.dart';

@immutable
class AudioPlaybackState {
  final LocalSong? currentSong;
  final bool isPlaying;
  final bool isLoading;
  final int currentIndex;
  final List<LocalSong> currentPlaylist;
  final ProcessingState processingState;
  final Duration duration;
  final LoopMode loopMode;
  final bool shuffleEnabled;
  final double speed;

  const AudioPlaybackState({
    this.currentSong,
    this.isPlaying = false,
    this.isLoading = false,
    this.currentIndex = 0,
    this.currentPlaylist = const [],
    this.processingState = ProcessingState.idle,
    this.duration = Duration.zero,
    this.loopMode = LoopMode.off,
    this.shuffleEnabled = false,
    this.speed = 1.0,
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
    LoopMode? loopMode,
    bool? shuffleEnabled,
    double? speed,
  }) {
    return AudioPlaybackState(
      currentSong: clearCurrentSong ? null : currentSong ?? this.currentSong,
      isPlaying: isPlaying ?? this.isPlaying,
      isLoading: isLoading ?? this.isLoading,
      currentIndex: currentIndex ?? this.currentIndex,
      currentPlaylist: currentPlaylist ?? this.currentPlaylist,
      processingState: processingState ?? this.processingState,
      duration: duration ?? this.duration,
      loopMode: loopMode ?? this.loopMode,
      shuffleEnabled: shuffleEnabled ?? this.shuffleEnabled,
      speed: speed ?? this.speed,
    );
  }
}
