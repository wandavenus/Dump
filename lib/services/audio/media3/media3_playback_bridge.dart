import 'package:flutter/services.dart';

import '../../../models/local_song.dart';
import 'media3_audio_player.dart'
    show AndroidEqualizerBand, AndroidEqualizerParameters;

/// Flutter ↔ Android Media3 bridge.
///
/// All DSP, buffering, playback scheduling, and audio processing is handled
/// natively inside `Media3PlaybackService.kt`. This class is the sole
/// MethodChannel / EventChannel edge. The UI talks to `AudioService`; this
/// class is an implementation detail.
class Media3PlaybackBridge {
  Media3PlaybackBridge._();

  static const MethodChannel _commands = MethodChannel(
    'musicplayer/media3_playback',
  );

  // ── EventChannels ──────────────────────────────────────────────────────────

  static const EventChannel _playbackStateEvents  = EventChannel('musicplayer/media3_playbackState');
  static const EventChannel _positionEvents        = EventChannel('musicplayer/media3_position');
  static const EventChannel _durationEvents        = EventChannel('musicplayer/media3_duration');
  static const EventChannel _currentTrackEvents    = EventChannel('musicplayer/media3_currentTrack');
  static const EventChannel _queueEvents           = EventChannel('musicplayer/media3_queue');
  static const EventChannel _bufferingStateEvents  = EventChannel('musicplayer/media3_bufferingState');
  static const EventChannel _audioSessionIdEvents  = EventChannel('musicplayer/media3_audioSessionId');
  static const EventChannel _shuffleModeEvents     = EventChannel('musicplayer/media3_shuffleMode');
  static const EventChannel _repeatModeEvents      = EventChannel('musicplayer/media3_repeatMode');
  static const EventChannel _sleepTimerEvents      = EventChannel('musicplayer/media3_sleepTimer');

  // Keep deprecated public refs for callers that use them directly.
  static const EventChannel playbackStateEvents   = _playbackStateEvents;
  static const EventChannel positionEvents         = _positionEvents;
  static const EventChannel durationEvents         = _durationEvents;
  static const EventChannel currentTrackEvents     = _currentTrackEvents;
  static const EventChannel queueEvents            = _queueEvents;
  static const EventChannel bufferingStateEvents   = _bufferingStateEvents;
  static const EventChannel audioSessionIdEvents   = _audioSessionIdEvents;

  // ── Streams ────────────────────────────────────────────────────────────────

  static final Stream<Map<dynamic, dynamic>> playbackStateStream =
    _playbackStateEvents
        .receiveBroadcastStream()
        .where((e) => e is Map)
        .cast<Map<dynamic, dynamic>>()
        .asBroadcastStream();

static final Stream<Duration> positionStream = _positionEvents
    .receiveBroadcastStream()
    .where((e) => e is num)
    .map((e) => Duration(milliseconds: (e as num).toInt()))
    .asBroadcastStream();

static final Stream<Duration> durationStream = _durationEvents
    .receiveBroadcastStream()
    .where((e) => e is num)
    .map((e) => Duration(milliseconds: (e as num).toInt()))
    .asBroadcastStream();

static final Stream<Map<dynamic, dynamic>?> currentTrackStream =
    _currentTrackEvents
        .receiveBroadcastStream()
        .where((e) => e == null || e is Map)
        .cast<Map<dynamic, dynamic>?>()
        .asBroadcastStream();

static final Stream<List<dynamic>> queueStream = _queueEvents
    .receiveBroadcastStream()
    .where((e) => e is List)
    .cast<List<dynamic>>()
    .asBroadcastStream();

static final Stream<bool> bufferingStateStream = _bufferingStateEvents
    .receiveBroadcastStream()
    .where((e) => e is bool)
    .cast<bool>()
    .asBroadcastStream();

static final Stream<int> audioSessionIdStream = _audioSessionIdEvents
    .receiveBroadcastStream()
    .where((e) => e is num)
    .map((e) => (e as num).toInt())
    .asBroadcastStream();

static final Stream<bool> shuffleModeStream = _shuffleModeEvents
    .receiveBroadcastStream()
    .where((e) => e is bool)
    .cast<bool>()
    .asBroadcastStream();

static final Stream<String> repeatModeStream = _repeatModeEvents
    .receiveBroadcastStream()
    .where((e) => e is String)
    .cast<String>()
    .asBroadcastStream();

static final Stream<Map<dynamic, dynamic>> sleepTimerStream =
    _sleepTimerEvents
        .receiveBroadcastStream()
        .where((e) => e is Map)
        .cast<Map<dynamic, dynamic>>()
        .asBroadcastStream();
  // ── Internal invoke with retry ─────────────────────────────────────────────
  //
  // MIUI 12 / Android 11: the native service starts asynchronously.
  // Back-off: 200 ms → 400 ms → 800 ms → 1600 ms (5 attempts total).

  static Future<T?> _invoke<T>(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        return await _commands.invokeMethod<T>(method, arguments);
      } on PlatformException catch (error) {
        if (error.code != 'not_ready' || attempt == 4) rethrow;
        await Future<void>.delayed(
            Duration(milliseconds: 200 * (1 << attempt)));
      }
    }
    return null;
  }

  // ── Playback transport ─────────────────────────────────────────────────────

  static Future<void> play()           => _invoke<void>('play');
  static Future<void> pause()          => _invoke<void>('pause');
  static Future<void> stop()           => _invoke<void>('stop');
  static Future<void> seek(Duration position) =>
      _invoke<void>('seek', {'position': position.inMilliseconds});
  static Future<void> skipNext()       => _invoke<void>('skipNext');
  static Future<void> skipPrevious()   => _invoke<void>('skipPrevious');
  static Future<void> setTrack(int index) =>
      _invoke<void>('setTrack', {'index': index});
  static Future<void> setQueue(List<LocalSong> queue, int index) =>
      _invoke<void>('setQueue', {
        'queue': queue.map((s) => s.toMap()).toList(),
        'index': index,
      });
  static Future<void> setRepeatMode(String mode) =>
      _invoke<void>('setRepeatMode', {'mode': mode});
  static Future<void> setShuffleMode(bool enabled) =>
      _invoke<void>('setShuffleMode', {'enabled': enabled});
  static Future<void> setVolume(double volume) =>
      _invoke<void>('setVolume', {'volume': volume});

  // ── Queue mutations (native owns the queue) ────────────────────────────────

  /// Insert [song] immediately after the currently playing track.
  static Future<void> insertNext(LocalSong song) =>
      _invoke<void>('insertNext', {'song': song.toMap()});

  /// Append [song] at the end of the queue.
  static Future<void> appendToQueue(LocalSong song) =>
      _invoke<void>('appendToQueue', {'song': song.toMap()});

  /// Remove the item at [index] from the queue.
  static Future<void> removeFromQueue(int index) =>
      _invoke<void>('removeFromQueue', {'index': index});

  /// Move the item at [oldIndex] to [newIndex].
  static Future<void> reorderQueue(int oldIndex, int newIndex) =>
      _invoke<void>('reorderQueue', {
        'oldIndex': oldIndex,
        'newIndex': newIndex,
      });

  // ── Playback parameters ────────────────────────────────────────────────────

  static Future<void> setSpeed(double speed) =>
      _invoke<void>('setSpeed', {'speed': speed});
  static Future<void> setPitch(double pitch) =>
      _invoke<void>('setPitch', {'pitch': pitch});

  // ── Equalizer ─────────────────────────────────────────────────────────────

  static Future<void> setEqualizerEnabled(bool enabled) =>
      _invoke<void>('setEqualizerEnabled', {'enabled': enabled});
  static Future<void> setEqualizerBandGain(int band, double gainDb) =>
      _invoke<void>('setEqualizerBandGain', {'band': band, 'gainDb': gainDb});

  static Future<AndroidEqualizerParameters> getEqualizerParameters() async {
    final rawDynamic = await _invoke<Map<dynamic, dynamic>>(
      'getEqualizerParameters',
    );
    final raw = rawDynamic?.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final bands = (raw?['bands'] as List<dynamic>? ?? const [0, 1, 2, 3, 4])
        .map((band) => AndroidEqualizerBand((band as num).toInt()))
        .toList();
    return AndroidEqualizerParameters(
      minDecibels: (raw?['minDecibels'] as num?)?.toDouble() ?? -15.0,
      maxDecibels: (raw?['maxDecibels'] as num?)?.toDouble() ?? 15.0,
      bands: bands,
    );
  }

  // ── Loudness / ReplayGain ─────────────────────────────────────────────────

  static Future<void> setLoudnessTargetGain(double gainMb) =>
      _invoke<void>('setLoudnessTargetGain', {'gainMb': gainMb});
  static Future<void> setLoudnessEnabled(bool enabled) =>
      _invoke<void>('setLoudnessEnabled', {'enabled': enabled});

  /// Send a pre-computed ReplayGain value to native.
  /// [gainDb] is in dB; native converts to millibels and applies via LoudnessEnhancer.
  static Future<void> setTrackGain({
    required bool enabled,
    required double gainDb,
  }) =>
      _invoke<void>('setTrackGain', {'enabled': enabled, 'gainDb': gainDb});

  // ── Bass Boost ─────────────────────────────────────────────────────────────

  static Future<void> setBassBoostEnabled(bool enabled) =>
      _invoke<void>('setBassBoostEnabled', {'enabled': enabled});
  static Future<void> setBassBoostStrength(int strength) =>
      _invoke<void>('setBassBoostStrength', {'strength': strength});

  // ── Virtualizer / Spatial Audio ────────────────────────────────────────────

  static Future<void> setVirtualizerEnabled(bool enabled) =>
      _invoke<void>('setVirtualizerEnabled', {'enabled': enabled});
  static Future<void> setVirtualizerStrength(int strength) =>
      _invoke<void>('setVirtualizerStrength', {'strength': strength});

  // ── Reverb ────────────────────────────────────────────────────────────────

  static Future<void> setReverbPreset(int preset) =>
      _invoke<void>('setReverbPreset', {'preset': preset});

  // ── Audio Offload ─────────────────────────────────────────────────────────

  /// Enable or disable audio offload scheduling.
  ///
  /// When disabled the ExoPlayer render loop runs at normal CPU priority and
  /// offload scheduling is never granted even when the OS would allow it.
  /// Use this as an escape hatch on devices where the offload path is unstable.
  static Future<void> setOffloadSchedulingEnabled(bool enabled) =>
      _invoke<void>('setOffloadSchedulingEnabled', {'enabled': enabled});

  // ── Crossfade ─────────────────────────────────────────────────────────────

  static Future<void> setCrossfadeDuration(double seconds) =>
      _invoke<void>('setCrossfadeDuration', {'duration': seconds});

  // ── Sleep timer ────────────────────────────────────────────────────────────

  /// Start a duration-based sleep timer. [durationMs] in milliseconds.
  static Future<void> setSleepTimer(int durationMs) =>
      _invoke<void>('setSleepTimer', {'durationMs': durationMs});

  /// Start end-of-song sleep timer — pauses after the current track ends.
  static Future<void> setSleepTimerEndOfSong() =>
      _invoke<void>('setSleepTimerEndOfSong');

  /// Cancel any active sleep timer.
  static Future<void> cancelSleepTimer() =>
      _invoke<void>('cancelSleepTimer');

  // ── Effect support query ───────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> getEffectSupport() async {
    try {
      final raw = await _invoke<Map<dynamic, dynamic>>('getEffectSupport');
      return raw?.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {
      return null;
    }
  }

  // ── State snapshot ─────────────────────────────────────────────────────────

  /// Pull a complete playback snapshot from the running native service.
  static Future<Map<String, dynamic>?> getPlaybackSnapshot() async {
    try {
      final raw = await _invoke<Map<dynamic, dynamic>>('getPlaybackSnapshot');
      if (raw == null) return null;
      return raw.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {
      return null;
    }
  }
}
