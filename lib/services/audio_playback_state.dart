import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

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

  const AudioPlaybackState({
    this.currentSong,
    this.isPlaying = false,
    this.isLoading = false,
    this.currentIndex = 0,
    this.currentPlaylist = const [],
    this.processingState = ProcessingState.idle,
    this.duration = Duration.zero,
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
  }) {
    return AudioPlaybackState(
      currentSong: clearCurrentSong ? null : currentSong ?? this.currentSong,
      isPlaying: isPlaying ?? this.isPlaying,
      isLoading: isLoading ?? this.isLoading,
      currentIndex: currentIndex ?? this.currentIndex,
      currentPlaylist: currentPlaylist ?? this.currentPlaylist,
      processingState: processingState ?? this.processingState,
      duration: duration ?? this.duration,
    );
  }
}
