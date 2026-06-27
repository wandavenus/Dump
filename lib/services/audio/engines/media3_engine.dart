import 'dart:async';

import '../../../models/local_song.dart';
import '../../log_service.dart';
import '../engine_abstraction.dart';
import '../media3/media3_playback_bridge.dart';

/// Engine wrapping the native Media3 / ExoPlayer implementation.
///
/// All DSP, crossfade, queue management, and audio processing remain in
/// Kotlin inside [Media3PlaybackService].  This class forwards commands
/// and stream subscriptions through [Media3PlaybackBridge].
///
/// ENCAPSULATION RULE:
///   [Media3PlaybackBridge] is the ONLY class that may communicate with the
///   Android MethodChannel / EventChannel playback layer.  This file is the
///   only Dart file that may import [Media3PlaybackBridge].
class Media3Engine implements AbstractAudioEngine {
  bool _initialized = false;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  Future<void> initialize() async {
    _initialized = true;
    LogService.log('Media3Engine', 'Initialized');
  }

  /// Performs a complete Media3 service teardown.
  ///
  /// Shutdown sequence (verified from Kotlin source):
  ///   1. Guards against double-dispose by clearing [_initialized] first.
  ///   2. Calls [Media3PlaybackBridge.release] → MethodChannel "release" →
  ///      Media3PlaybackService.handle() which:
  ///        a. Cancels crossfade and sleep timer.
  ///        b. Abandons audio focus.
  ///        c. Removes the playback notification / exits foreground service.
  ///        d. Returns result.success(null) to Dart.
  ///        e. Calls stopSelf() → Android schedules onDestroy().
  ///   3. onDestroy() then performs the full resource release:
  ///        • effectsManager.releaseEffects()
  ///        • handler.removeCallbacksAndMessages()
  ///        • unregisterReceiver(noisyReceiver)
  ///        • audioCapReceiver.unregister()
  ///        • primaryPlayer.release() + secondaryPlayer.release()
  ///        • session.release()
  ///
  /// No artificial delay is needed: result.success(null) is sent before
  /// stopSelf() so Dart receives the acknowledgement while the service is
  /// still fully alive.  onDestroy() runs asynchronously on the main looper
  /// after this method returns.
  ///
  /// Stream subscriptions held by [AudioEngineManager] are cancelled by the
  /// manager before [dispose] is called, so no orphan listeners remain.
  @override
  Future<void> dispose() async {
    if (!_initialized) return;
    // Set false before any await to prevent concurrent double-dispose.
    _initialized = false;
    LogService.log('Media3Engine', 'Disposing — initiating complete native teardown');
    try {
      await Media3PlaybackBridge.release();
    } catch (e) {
      // Native side may already be stopped — safe to ignore.
      LogService.warn('Media3Engine', 'dispose() release error (ignored): $e');
    }
    LogService.log('Media3Engine', 'Disposed — native service teardown initiated');
  }

  // ── Transport ─────────────────────────────────────────────────────────────

  @override
  Future<void> play() => Media3PlaybackBridge.play();

  @override
  Future<void> pause() => Media3PlaybackBridge.pause();

  @override
  Future<void> stop() => Media3PlaybackBridge.stop();

  @override
  Future<void> seek(Duration position) => Media3PlaybackBridge.seek(position);

  // ── Queue ─────────────────────────────────────────────────────────────────

  @override
  Future<void> setQueue(List<LocalSong> queue, int index) =>
      Media3PlaybackBridge.setQueue(queue, index);

  @override
  Future<void> skipNext() => Media3PlaybackBridge.skipNext();

  @override
  Future<void> skipPrevious() => Media3PlaybackBridge.skipPrevious();

  @override
  Future<void> setTrack(int index) => Media3PlaybackBridge.setTrack(index);

  // ── Queue mutations ───────────────────────────────────────────────────────

  @override
  Future<void> insertNext(LocalSong song) =>
      Media3PlaybackBridge.insertNext(song);

  @override
  Future<void> appendToQueue(LocalSong song) =>
      Media3PlaybackBridge.appendToQueue(song);

  @override
  Future<void> removeFromQueue(int index) =>
      Media3PlaybackBridge.removeFromQueue(index);

  @override
  Future<void> reorderQueue(int oldIndex, int newIndex) =>
      Media3PlaybackBridge.reorderQueue(oldIndex, newIndex);

  // ── Mode ──────────────────────────────────────────────────────────────────

  @override
  Future<void> setRepeatMode(String mode) =>
      Media3PlaybackBridge.setRepeatMode(mode);

  @override
  Future<void> setShuffleMode(bool enabled) =>
      Media3PlaybackBridge.setShuffleMode(enabled);

  // ── Playback parameters ───────────────────────────────────────────────────

  @override
  Future<void> setVolume(double volume) =>
      Media3PlaybackBridge.setVolume(volume);

  @override
  Future<void> setSpeed(double speed) => Media3PlaybackBridge.setSpeed(speed);

  @override
  Future<void> setPitch(double pitch) => Media3PlaybackBridge.setPitch(pitch);

  // ── DSP effects ───────────────────────────────────────────────────────────

  @override
  Future<void> setBassBoost(int strength) =>
      Media3PlaybackBridge.setBassBoostStrength(strength);

  @override
  Future<void> setBassBoostEnabled(bool enabled) =>
      Media3PlaybackBridge.setBassBoostEnabled(enabled);

  @override
  Future<void> setVirtualizerEnabled(bool enabled) =>
      Media3PlaybackBridge.setVirtualizerEnabled(enabled);

  @override
  Future<void> setVirtualizerStrength(int strength) =>
      Media3PlaybackBridge.setVirtualizerStrength(strength);

  @override
  Future<void> setReverbPreset(int preset) =>
      Media3PlaybackBridge.setReverbPreset(preset);

  @override
  Future<void> setEqualizerEnabled(bool enabled) =>
      Media3PlaybackBridge.setEqualizerEnabled(enabled);

  @override
  Future<void> setEqualizerBandGain(int band, double gainDb) =>
      Media3PlaybackBridge.setEqualizerBandGain(band, gainDb);

  @override
  Future<void> setLoudnessEnabled(bool enabled) =>
      Media3PlaybackBridge.setLoudnessEnabled(enabled);

  @override
  Future<void> setLoudnessTargetGain(double gainMb) =>
      Media3PlaybackBridge.setLoudnessTargetGain(gainMb);

  @override
  Future<void> setCrossfadeDuration(double seconds) =>
      Media3PlaybackBridge.setCrossfadeDuration(seconds);

  @override
  Future<EngineEqualizerParameters?> getEqualizerParameters() async {
    try {
      final raw = await Media3PlaybackBridge.getEqualizerParameters();
      return EngineEqualizerParameters(
        minDecibels: raw.minDecibels,
        maxDecibels: raw.maxDecibels,
        bandCount:   raw.bands.length,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>?> getEffectSupport() =>
      Media3PlaybackBridge.getEffectSupport();

  // ── Capabilities ─────────────────────────────────────────────────────────

  @override
  Future<void> setSkipSilence(bool enabled) =>
      Media3PlaybackBridge.setSkipSilence(enabled);

  @override
  Future<void> setStereoWidening({
    required bool enabled,
    required double strength,
  }) =>
      Media3PlaybackBridge.setStereoWidening(
        enabled:  enabled,
        strength: strength,
      );

  @override
  Future<Map<String, dynamic>?> getPlaybackStats() =>
      Media3PlaybackBridge.getPlaybackStats();

  // ── Audio format ─────────────────────────────────────────────────────────

  @override
  Future<Map<String, dynamic>?> getAudioFormat() =>
      Media3PlaybackBridge.getAudioFormat();

  // ── Sleep timer ───────────────────────────────────────────────────────────

  @override
  Future<void> setSleepTimer(int durationMs) =>
      Media3PlaybackBridge.setSleepTimer(durationMs);

  @override
  Future<void> setSleepTimerEndOfSong() =>
      Media3PlaybackBridge.setSleepTimerEndOfSong();

  @override
  Future<void> cancelSleepTimer() => Media3PlaybackBridge.cancelSleepTimer();

  // ── State snapshot ────────────────────────────────────────────────────────

  @override
  Future<Map<String, dynamic>?> getPlaybackSnapshot() =>
      Media3PlaybackBridge.getPlaybackSnapshot();

  // ── Streams ───────────────────────────────────────────────────────────────

  @override
  Stream<Map<dynamic, dynamic>> get playbackStateStream =>
      Media3PlaybackBridge.playbackStateStream;

  @override
  Stream<Duration> get positionStream => Media3PlaybackBridge.positionStream;

  @override
  Stream<Duration> get durationStream => Media3PlaybackBridge.durationStream;

  @override
  Stream<Map<dynamic, dynamic>?> get currentTrackStream =>
      Media3PlaybackBridge.currentTrackStream;

  @override
  Stream<List<dynamic>> get queueStream => Media3PlaybackBridge.queueStream;

  @override
  Stream<bool> get bufferingStateStream =>
      Media3PlaybackBridge.bufferingStateStream;

  @override
  Stream<bool> get shuffleModeStream => Media3PlaybackBridge.shuffleModeStream;

  @override
  Stream<String> get repeatModeStream => Media3PlaybackBridge.repeatModeStream;

  @override
  Stream<Map<dynamic, dynamic>> get sleepTimerStream =>
      Media3PlaybackBridge.sleepTimerStream;

  @override
  Stream<int> get audioSessionIdStream =>
      Media3PlaybackBridge.audioSessionIdStream;

  @override
  Stream<Map<dynamic, dynamic>> get audioFormatStream =>
      Media3PlaybackBridge.audioFormatStream;

  @override
  Stream<bool> get skipSilenceStream => Media3PlaybackBridge.skipSilenceStream;

  @override
  Stream<Map<dynamic, dynamic>> get stereoWideningStream =>
      Media3PlaybackBridge.stereoWideningStream;

  bool get isInitialized => _initialized;
}
