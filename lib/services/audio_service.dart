import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

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

class AudioService {
  AudioService._();

  static final AudioPlayer player = AudioPlayer();
  static final ValueNotifier<AudioPlaybackState> playbackState =
      ValueNotifier<AudioPlaybackState>(const AudioPlaybackState());

  static bool _initialized = false;
  static bool _isLoading = false;
  static final List<StreamSubscription<dynamic>> _subscriptions = [];

  static LocalSong? get currentSong => playbackState.value.currentSong;
  static bool get isPlaying => playbackState.value.isPlaying;
  static int get currentIndex => playbackState.value.currentIndex;
  static List<LocalSong> get currentPlaylist =>
      playbackState.value.currentPlaylist;

  static set currentSong(LocalSong? song) {
    _setState(playbackState.value.copyWith(
      currentSong: song,
      clearCurrentSong: song == null,
    ));
  }

  static set isPlaying(bool value) {
    _setState(playbackState.value.copyWith(isPlaying: value));
  }

  static set currentIndex(int value) {
    _setState(playbackState.value.copyWith(currentIndex: value));
  }

  static set currentPlaylist(List<LocalSong> value) {
    _setState(playbackState.value.copyWith(
      currentPlaylist: List<LocalSong>.unmodifiable(value),
    ));
  }

  static void initialize() {
    if (_initialized) return;
    _initialized = true;

    _subscriptions.add(
      player.playerStateStream.listen((PlayerState state) {
        _setState(
          playbackState.value.copyWith(
            isPlaying: state.playing,
            processingState: state.processingState,
          ),
        );

        if (state.processingState == ProcessingState.completed) {
          _playNextAfterCompletion();
        }
      }),
    );

    _subscriptions.add(
      player.durationStream.listen((Duration? duration) {
        _setState(
          playbackState.value.copyWith(
            duration: duration ?? Duration.zero,
          ),
        );
      }),
    );

    _syncPlaybackState();
  }

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

    _setState(
      playbackState.value.copyWith(
        currentSong: selectedSong,
        currentIndex: index,
        currentPlaylist: immutablePlaylist,
        isLoading: true,
      ),
    );

    try {
      await player.stop();
      await player.setAudioSource(
        AudioSource.file(
          selectedSong.path,
          tag: _mediaItemFor(selectedSong),
        ),
      );

      if (autoplay) {
        await player.play();
      }

      _syncPlaybackState();
    } finally {
      _isLoading = false;
      _setState(playbackState.value.copyWith(isLoading: false));
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
    final state = playbackState.value;
    if (state.currentIndex >= state.currentPlaylist.length - 1) return;

    await playSongAt(
      playlist: state.currentPlaylist,
      index: state.currentIndex + 1,
    );
  }

  static Future<void> skipPrevious() async {
    final state = playbackState.value;
    if (state.currentIndex <= 0) return;

    await playSongAt(
      playlist: state.currentPlaylist,
      index: state.currentIndex - 1,
    );
  }

  static Future<void> playFromCurrentQueue(int index) async {
    final state = playbackState.value;
    await playSongAt(
      playlist: state.currentPlaylist,
      index: index,
    );
  }

  static Future<void> _playNextAfterCompletion() async {
    final state = playbackState.value;
    if (_isLoading || state.currentIndex >= state.currentPlaylist.length - 1) {
      return;
    }

    await skipNext();
  }

  static void _syncPlaybackState() {
    _setState(
      playbackState.value.copyWith(
        isPlaying: player.playing,
        processingState: player.processingState,
      ),
    );
  }

  static MediaItem _mediaItemFor(LocalSong song) {
    return MediaItem(
      id: song.id.toString(),
      title: song.title,
      artist: song.artist,
      album: song.album,
      duration: song.duration,
      artUri: song.albumId > 0
          ? Uri.parse('content://media/external/audio/albumart/${song.albumId}')
          : null,
    );
  }

  static void _setState(AudioPlaybackState state) {
    playbackState.value = state;
  }

  static Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    _initialized = false;
    await player.dispose();
  }
}
