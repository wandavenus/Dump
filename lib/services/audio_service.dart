import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/local_song.dart';
import 'audio_playback_state.dart';
import 'audio_source_builder.dart';

class AudioService {
  AudioService._();

  static final AudioPlayer player = AudioPlayer();
 static ConcatenatingAudioSource? _queue;
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

  _subscriptions.add(
  player.currentIndexStream.listen((index) {
    if (index == null) return;

    final playlist = playbackState.value.currentPlaylist;

    if (index < 0 || index >= playlist.length) return;

    _setState(
      playbackState.value.copyWith(
        currentIndex: index,
        currentSong: playlist[index],
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
      _queue = ConcatenatingAudioSource(
  children: immutablePlaylist
      .map(buildAudioSource)
      .toList(),
);

await player.stop();
await player.setAudioSource(
  _queue!,
  initialIndex: index,
);

      if (autoplay) {
        await player.play();
      }
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
  await player.seekToNext();
}

  static Future<void> skipPrevious() async {
  await player.seekToPrevious();
}

  static Future<void>
 playFromCurrentQueue(int index) async {
  await player.seek(
    Duration.zero,
    index: index,
  );

  if (!player.playing) {
    await player.play();
  }
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
