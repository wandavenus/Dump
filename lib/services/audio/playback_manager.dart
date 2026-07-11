// ignore_for_file: close_sinks

import 'dart:async';

import '../artwork_repository.dart';
import '../palette_extractor.dart';
import '../../models/local_song.dart';
import '../log_service.dart';
import 'media3/media3_playback_bridge.dart';
import '../native/bridges/native_dsp_bridge.dart';
import '../native/bridges/ffmpeg_decoder_bridge.dart';
import '../native/contracts/native_module.dart';
import '../native/native_module_registry.dart';

// ─── Equalizer parameter type ─────────────────────────────────────────────────

class EqualizerParameters {
  final double minDecibels;
  final double maxDecibels;
  final int bandCount;

  const EqualizerParameters({
    required this.minDecibels,
    required this.maxDecibels,
    required this.bandCount,
  });
}

// ─── PlaybackManager ─────────────────────────────────────────────────────────

/// Central playback facade — single engine (Media3 / ExoPlayer).
///
/// All UI and service layers communicate through [PlaybackManager].
/// Internally delegates directly to [Media3PlaybackBridge].
///
/// Architecture:
///   Flutter UI
///     ↓
///   AudioService       (business-logic facade)
///     ↓
///   PlaybackManager    (this class — stream routing + artwork prefetch)
///     ↓
///   Media3PlaybackBridge  (sole MethodChannel / EventChannel edge)
///     ↓
///   Media3PlaybackService.kt → ExoPlayer
///
/// Extension points for future native modules (C++ DSP, FFmpeg decoder)
/// are intended as additional slots in [Media3PlaybackBridge] or as
/// separate Dart ↔ Native bridges, keeping business logic decoupled.
///
/// Stream format contracts (unchanged):
/// [playbackStateStream] → Map: 'playing' bool, 'processingState' String
/// [currentTrackStream]  → Map?: 'index' int, 'id' int, 'nextTrackIndex' int
/// [queueStream]         → List of LocalSong.toMap()
/// [sleepTimerStream]    → Map: 'active' bool, 'endOfSong' bool, 'remainingMs' int
class PlaybackManager {
  PlaybackManager._();

  static bool _initialized = false;

  // ── Artwork prefetch state ─────────────────────────────────────────────────
  static List<LocalSong> _currentQueue = const [];
  static int _lastPrefetchedIndex = -1;
  static final Set<int> _prefetchingSongs = <int>{};
  static int _activePrefetches = 0;
  static const int _maxConcurrentPrefetches = 2;

  // ── Forwarding stream controllers (currentTrack / queue intercepted) ───────
  //
  // These two streams are intercepted to maintain the local queue mirror
  // (_currentQueue) used for artwork prefetching.  All other streams are
  // exposed as direct pass-throughs from [Media3PlaybackBridge].
  static final _currentTrackCtrl =
      StreamController<Map<dynamic, dynamic>?>.broadcast();
  static final _queueCtrl = StreamController<List<dynamic>>.broadcast();

  static final List<StreamSubscription<dynamic>> _subs = [];

  // ── Public streams ─────────────────────────────────────────────────────────

  static Stream<Map<dynamic, dynamic>> get playbackStateStream =>
      Media3PlaybackBridge.playbackStateStream;
  static Stream<Duration> get positionStream =>
      Media3PlaybackBridge.positionStream;
  static Stream<Duration> get durationStream =>
      Media3PlaybackBridge.durationStream;
  static Stream<Map<dynamic, dynamic>?> get currentTrackStream =>
      _currentTrackCtrl.stream;
  static Stream<List<dynamic>> get queueStream => _queueCtrl.stream;
  static Stream<bool> get bufferingStateStream =>
      Media3PlaybackBridge.bufferingStateStream;
  static Stream<bool> get shuffleModeStream =>
      Media3PlaybackBridge.shuffleModeStream;
  static Stream<String> get repeatModeStream =>
      Media3PlaybackBridge.repeatModeStream;
  static Stream<Map<dynamic, dynamic>> get sleepTimerStream =>
      Media3PlaybackBridge.sleepTimerStream;
  static Stream<int> get audioSessionIdStream =>
      Media3PlaybackBridge.audioSessionIdStream;
  static Stream<Map<dynamic, dynamic>> get audioFormatStream =>
      Media3PlaybackBridge.audioFormatStream;
  static Stream<bool> get skipSilenceStream =>
      Media3PlaybackBridge.skipSilenceStream;
  static Stream<Map<dynamic, dynamic>> get stereoWideningStream =>
      Media3PlaybackBridge.stereoWideningStream;

  // ── Init ──────────────────────────────────────────────────────────────────

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Subscribe to currentTrack: forward events and trigger artwork prefetch.
    _subs.add(
      Media3PlaybackBridge.currentTrackStream.listen((event) {
        _currentTrackCtrl.add(event);

        final currentIndex = (event?['index'] as num?)?.toInt() ?? -1;
        if (currentIndex < 0) return;
        if (_lastPrefetchedIndex == currentIndex) return;
        _lastPrefetchedIndex = currentIndex;

        for (var i = -1; i <= 3; i++) {
          unawaited(_prefetchArtwork(currentIndex + i));
        }
      }),
    );

    // Subscribe to queue: forward events, mirror queue, seed artwork prefetch.
    _subs.add(
      Media3PlaybackBridge.queueStream.listen((queue) {
        _queueCtrl.add(queue);

        _currentQueue = queue
            .whereType<Map>()
            .map((m) => LocalSong.fromMap(m.cast<dynamic, dynamic>()))
            .toList();

        for (var i = 0; i < _currentQueue.length && i < 3; i++) {
          unawaited(_prefetchArtwork(i));
        }
      }),
    );

    LogService.log(
      'PlaybackManager',
      'Initialized — Media3PlaybackBridge (single engine)',
    );
  }

  // ── Transport ─────────────────────────────────────────────────────────────

  static Future<void> play()           => Media3PlaybackBridge.play();
  static Future<void> pause()          => Media3PlaybackBridge.pause();
  static Future<void> stop()           => Media3PlaybackBridge.stop();
  static Future<void> seek(Duration p) => Media3PlaybackBridge.seek(p);
  static Future<void> skipNext()       => Media3PlaybackBridge.skipNext();
  static Future<void> skipPrevious()   => Media3PlaybackBridge.skipPrevious();
  static Future<void> setTrack(int i)  => Media3PlaybackBridge.setTrack(i);

  // ── Mode ──────────────────────────────────────────────────────────────────

  static Future<void> setRepeatMode(String m) =>
      Media3PlaybackBridge.setRepeatMode(m);
  static Future<void> setShuffleMode(bool e) =>
      Media3PlaybackBridge.setShuffleMode(e);

  // ── Playback parameters ───────────────────────────────────────────────────

  static Future<void> setVolume(double v) => Media3PlaybackBridge.setVolume(v);
  static Future<void> setSpeed(double v)  => Media3PlaybackBridge.setSpeed(v);
  static Future<void> setPitch(double v)  => Media3PlaybackBridge.setPitch(v);

  // ── Queue mutations ───────────────────────────────────────────────────────

  static Future<void> setQueue(List<LocalSong> q, int i) =>
      Media3PlaybackBridge.setQueue(q, i);
  static Future<void> insertNext(LocalSong s) =>
      Media3PlaybackBridge.insertNext(s);
  static Future<void> appendToQueue(LocalSong s) =>
      Media3PlaybackBridge.appendToQueue(s);
  static Future<void> removeFromQueue(int i) =>
      Media3PlaybackBridge.removeFromQueue(i);
  static Future<void> reorderQueue(int o, int n) =>
      Media3PlaybackBridge.reorderQueue(o, n);

  // ── DSP effects ───────────────────────────────────────────────────────────

  static Future<void> setBassBoost(int strength) =>
      Media3PlaybackBridge.setBassBoostStrength(strength);
  static Future<void> setBassBoostEnabled(bool e) =>
      Media3PlaybackBridge.setBassBoostEnabled(e);
  static Future<void> setVirtualizerEnabled(bool e) =>
      Media3PlaybackBridge.setVirtualizerEnabled(e);
  static Future<void> setVirtualizerStrength(int s) =>
      Media3PlaybackBridge.setVirtualizerStrength(s);
  static Future<void> setEqualizerEnabled(bool e) =>
      Media3PlaybackBridge.setEqualizerEnabled(e);
  static Future<void> setEqualizerBandGain(int b, double g) =>
      Media3PlaybackBridge.setEqualizerBandGain(b, g);
  static Future<void> setLoudnessEnabled(bool e) =>
      Media3PlaybackBridge.setLoudnessEnabled(e);
  static Future<void> setLoudnessTargetGain(double g) =>
      Media3PlaybackBridge.setLoudnessTargetGain(g);
  static Future<void> setCrossfadeDuration(double s) =>
      Media3PlaybackBridge.setCrossfadeDuration(s);

  static Future<EqualizerParameters?> getEqualizerParameters() async {
    try {
      final raw = await Media3PlaybackBridge.getEqualizerParameters();
      return EqualizerParameters(
        minDecibels: raw.minDecibels,
        maxDecibels: raw.maxDecibels,
        bandCount: raw.bands.length,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getEffectSupport() =>
      Media3PlaybackBridge.getEffectSupport();

  // ── Capabilities ──────────────────────────────────────────────────────────

  static Future<void> setSkipSilence(bool e) =>
      Media3PlaybackBridge.setSkipSilence(e);

  static Future<void> setStereoWidening({
    required bool enabled,
    required double strength,
  }) =>
      Media3PlaybackBridge.setStereoWidening(
        enabled: enabled,
        strength: strength,
      );

  static Future<Map<String, dynamic>?> getPlaybackStats() =>
      Media3PlaybackBridge.getPlaybackStats();

  // ── Audio format ──────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> getAudioFormat() =>
      Media3PlaybackBridge.getAudioFormat();

  // ── Sleep timer ───────────────────────────────────────────────────────────

  static Future<void> setSleepTimer(int ms) =>
      Media3PlaybackBridge.setSleepTimer(ms);
  static Future<void> setSleepTimerEndOfSong() =>
      Media3PlaybackBridge.setSleepTimerEndOfSong();
  static Future<void> cancelSleepTimer() =>
      Media3PlaybackBridge.cancelSleepTimer();

  // ── State snapshot ────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> getPlaybackSnapshot() =>
      Media3PlaybackBridge.getPlaybackSnapshot();

  // ── Private helpers ───────────────────────────────────────────────────────

  static Future<void> _prefetchArtwork(int index) async {
    try {
      if (index < 0 || index >= _currentQueue.length) return;

      final song = _currentQueue[index];

      if (!_prefetchingSongs.add(song.id)) {
        return;
      }

      if (_activePrefetches >= _maxConcurrentPrefetches) {
        _prefetchingSongs.remove(song.id);
        return;
      }

      _activePrefetches++;

      if (PaletteExtractor.getSync(song.id) != null) {
        return;
      }

      final bytes = await ArtworkRepository.instance.getBytes(song.id);
      if (bytes == null) return;

      if (PaletteExtractor.getSync(song.id) != null) {
        return;
      }

      await PaletteExtractor.get(song.id, bytes);
    } catch (_) {
      // Ignore prefetch failures.
    } finally {
      if (index >= 0 && index < _currentQueue.length) {
        _prefetchingSongs.remove(_currentQueue[index].id);
        if (_activePrefetches > 0) {
          _activePrefetches--;
        }
      }
    }
  }
}
