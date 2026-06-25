import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/local_song.dart';
import 'audio/media3/media3_audio_player.dart';
import 'audio_playback_state.dart';
import 'audio_service.dart';

/// Injects a fake playback state directly into [AudioService.playbackState]
/// so the mini-player and player sheet can be previewed without a real
/// Android device or audio file.
///
/// Safe to use in web/browser preview — no native calls are made.
/// The native EventChannels are either not connected (web) or silent while
/// the timer ticks, so the simulated state holds.
class PlaybackSimulationService {
  PlaybackSimulationService._();

  static final ValueNotifier<bool> active = ValueNotifier(false);

  static int      _songIndex = 0;
  static Duration _position  = Duration.zero;
  static bool     _playing   = true;
  static Timer?   _ticker;

  // ── Fake song catalogue ───────────────────────────────────────────────────

  static const List<LocalSong> songs = [
    LocalSong(
      id: -1,
      title: 'Blinding Lights',
      artist: 'The Weeknd',
      path: '',
      album: 'After Hours',
      albumId: -1,
      duration: Duration(minutes: 3, seconds: 20),
      year: 2020,
      genre: 'Synthpop',
      bitrate: 320000,
      sampleRate: 44100,
    ),
    LocalSong(
      id: -2,
      title: 'Shape of You',
      artist: 'Ed Sheeran',
      path: '',
      album: '÷ (Divide)',
      albumId: -2,
      duration: Duration(minutes: 3, seconds: 53),
      year: 2017,
      genre: 'Pop',
      bitrate: 256000,
      sampleRate: 44100,
    ),
    LocalSong(
      id: -3,
      title: 'Bohemian Rhapsody',
      artist: 'Queen',
      path: '',
      album: 'A Night at the Opera',
      albumId: -3,
      duration: Duration(minutes: 5, seconds: 55),
      year: 1975,
      genre: 'Classic Rock',
      bitrate: 320000,
      sampleRate: 44100,
    ),
    LocalSong(
      id: -4,
      title: 'Levitating',
      artist: 'Dua Lipa',
      path: '',
      album: 'Future Nostalgia',
      albumId: -4,
      duration: Duration(minutes: 3, seconds: 23),
      year: 2020,
      genre: 'Disco Pop',
      bitrate: 320000,
      sampleRate: 48000,
    ),
    LocalSong(
      id: -5,
      title: 'Stay With Me',
      artist: 'Sam Smith',
      path: '',
      album: 'In the Lonely Hour',
      albumId: -5,
      duration: Duration(minutes: 2, seconds: 52),
      year: 2014,
      genre: 'Soul',
      bitrate: 320000,
      sampleRate: 44100,
    ),
  ];

  // ── Public API ────────────────────────────────────────────────────────────

  static void start() {
    if (active.value) return;
    _songIndex = 0;
    _position  = Duration.zero;
    _playing   = true;
    active.value = true;
    _pushState();
    _ticker = Timer.periodic(const Duration(seconds: 1), _tick);
  }

  static void stop() {
    _ticker?.cancel();
    _ticker = null;
    active.value = false;
    AudioService.playbackState.value = const AudioPlaybackState();
  }

  static void togglePlayPause() {
    _playing = !_playing;
    _pushState();
  }

  static void skipNext() {
    _songIndex = (_songIndex + 1) % songs.length;
    _position  = Duration.zero;
    _pushState();
  }

  static void skipPrev() {
    if (_position.inSeconds > 3) {
      _position = Duration.zero;
    } else {
      _songIndex = (_songIndex - 1 + songs.length) % songs.length;
      _position  = Duration.zero;
    }
    _pushState();
  }

  static void seek(Duration pos) {
    _position = pos.isNegative ? Duration.zero : pos;
    _pushState();
  }

  static void jumpToSong(int index) {
    _songIndex = index.clamp(0, songs.length - 1);
    _position  = Duration.zero;
    _pushState();
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  static void _tick(Timer _) {
    if (!_playing) return;
    final dur = songs[_songIndex].duration;
    _position += const Duration(seconds: 1);
    if (_position >= dur) {
      skipNext();
      return;
    }
    _pushState();
  }

  static void _pushState() {
    final song = songs[_songIndex];
    AudioService.playbackState.value = AudioPlaybackState(
      currentSong:      song,
      isPlaying:        _playing,
      isLoading:        false,
      currentIndex:     _songIndex,
      currentPlaylist:  songs,
      processingState:  ProcessingState.ready,
      duration:         song.duration,
      position:         _position,
      loopMode:         LoopMode.all,
      shuffleEnabled:   false,
      speed:            1.0,
    );
  }
}
