import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/local_song.dart';
import 'audio_playback_state.dart';
import 'audio_source_builder.dart';
import 'history_service.dart';
import 'log_service.dart';

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

        LogService.log('AudioService', 'Playing: ${playlist[index].title}');

        unawaited(HistoryService.trackPlay(playlist[index]));
      }),
    );

    _syncPlaybackState();
    LogService.log('AudioService', 'Initialized');
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
    await player.seekToNext();
    LogService.log('AudioService', 'Skip next');
  }

  static Future<void> skipPrevious() async {
    await player.seekToPrevious();
    LogService.log('AudioService', 'Skip previous');
  }

  static Future<void> playFromCurrentQueue(int index) async {
    await player.seek(Duration.zero, index: index);
    if (!player.playing) await player.play();
  }

  /// Tambah lagu sebagai item berikutnya di antrian (setelah lagu saat ini).
  static void addToQueueNext(LocalSong song) {
    if (_queue == null) return;
    final nextIndex = (currentIndex + 1).clamp(0, _queue!.length);
    _queue!.insert(nextIndex, buildAudioSource(song));
    final newPlaylist = List<LocalSong>.from(currentPlaylist)
      ..insert(nextIndex, song);
    _setState(playbackState.value.copyWith(
      currentPlaylist: List<LocalSong>.unmodifiable(newPlaylist),
    ));
    LogService.log('AudioService', 'Added to queue next: ${song.title}');
  }

  /// Tambah lagu ke akhir antrian.
  static void addToQueue(LocalSong song) {
    if (_queue == null) return;
    _queue!.add(buildAudioSource(song));
    final newPlaylist = List<LocalSong>.from(currentPlaylist)..add(song);
    _setState(playbackState.value.copyWith(
      currentPlaylist: List<LocalSong>.unmodifiable(newPlaylist),
    ));
    LogService.log('AudioService', 'Added to queue end: ${song.title}');
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
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    _initialized = false;
    await player.dispose();
  }
}
