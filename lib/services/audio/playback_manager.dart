// ignore_for_file: close_sinks

import 'dart:async';

import 'package:native_audio_runtime/native_audio_runtime.dart';

import '../artwork_repository.dart';
import '../palette_extractor.dart';
import '../../models/local_song.dart';
import '../log_service.dart';
import '../boot_trace.dart';
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
    BootTrace.log('ENTER PlaybackManager.initialize()');
    if (_initialized) {
      BootTrace.log('EXIT  PlaybackManager.initialize() — already initialized, no-op');
      return;
    }
    _initialized = true;

    // Register native modules (FFI runtime bridges — Media3 remains the only
    // active playback engine). Registration happens once, here, so
    // PlaybackManager stays the single owner of native module lifecycle.
    // See lib/services/native/NATIVE_BRIDGES.md and NATIVE_RUNTIME.md.
    NativeModuleRegistry.register(NativeDspBridge.instance);
    NativeModuleRegistry.register(FfmpegDecoderBridge.instance);
    BootTrace.log('BEFORE await NativeModuleRegistry.initializeAll()');
    await NativeModuleRegistry.initializeAll();
    BootTrace.log('AFTER  await NativeModuleRegistry.initializeAll()');

    // Initialize the Phase 4.5 native DSP pipeline (C-side: dsp_pipeline.c +
    // gain_processor.c). Wired into Media3's audio thread via
    // NativeDspAudioProcessor (first slot in DefaultAudioProcessorChain in
    // Media3PlaybackService.createConfiguredPlayer). A failure is non-fatal —
    // NativeDspAudioProcessor passes audio unchanged when the pipeline has not
    // yet been initialized (fail-open: nar_dsp_pipeline_process_raw returns
    // NATIVE_RUNTIME_ERROR_NOT_INITIALIZED without touching the buffer).
    BootTrace.log('BEFORE try/await NativeDspPipeline.instance.initialize()');
    try {
      await NativeDspPipeline.instance.initialize();
      BootTrace.log('AFTER  await NativeDspPipeline.instance.initialize() — ok');
      LogService.log(
        'PlaybackManager',
        'Native DSP pipeline initialized'
        ' (${NativeDspPipeline.instance.processorCount} processor(s))',
      );
    } catch (e, st) {
      BootTrace.log(
          'CAUGHT exception in NativeDspPipeline.instance.initialize(): $e\n$st');
      LogService.log(
        'PlaybackManager',
        'Native DSP pipeline unavailable (non-fatal): $e',
      );
    }

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

  // ── Native module access (FFI runtime) ───────────────────────────────────
  //
  // UI and services must never import `lib/services/native/bridges/` or
  // `package:native_audio_runtime` directly — this is the single sanctioned
  // entry point per NATIVE_BRIDGES.md.

  /// Snapshot of every registered native module (id, name, availability).
  static List<NativeModule> get nativeModules => NativeModuleRegistry.all;

  /// Aggregate capability report across all registered native modules.
  static Future<Map<String, List<NativeCapability>>>
      queryNativeCapabilities() => NativeModuleRegistry.queryAllCapabilities();

  // ── FFmpeg decoder (Phase 9) ──────────────────────────────────────────────
  //
  // The only sanctioned entry point for FFmpeg decoder status — see
  // FfmpegDecoderBridge's doc comment for the full architecture. This is the
  // one exception to "native access goes through PlaybackManager only" that
  // still holds: PlaybackManager talks to FfmpegDecoderBridge, never directly
  // to the ffmpeg_decoder MethodChannel/EventChannel.

  /// Capability snapshot detected at startup: whether the bundled FFmpeg
  /// build is available, its version, and which Phase 9 target codecs
  /// (ALAC/DTS/TrueHD/Vorbis/Opus) it actually supports.
  static FfmpegDecoderCapabilities get ffmpegDecoderCapabilities =>
      FfmpegDecoderBridge.instance.capabilities;

  /// Per-track decoder selection diagnostics for the active player — fires
  /// for every decoder init, whether it landed on a built-in MediaCodec or
  /// the FFmpeg fallback, each with a human-readable [FfmpegDecoderInfo.reason].
  static Stream<FfmpegDecoderInfo> get ffmpegDecoderInfoStream =>
      FfmpegDecoderBridge.instance.decoderInfoStream;

  // ── Native DSP pipeline (Phase 4) ─────────────────────────────────────────
  //
  // The C-side DSP pipeline (dsp_pipeline.c + gain_processor.c) is
  // architecture-only in Phase 4: the pipeline and gain processor are fully
  // implemented but not yet wired into Media3's audio thread. Controls here
  // let future UI / audio-engine code configure the pipeline without
  // importing native_audio_runtime directly.

  /// Whether the native DSP pipeline initialized successfully on this device.
  static bool get nativeDspAvailable =>
      NativeDspPipeline.instance.isInitialized;

  /// Set the gain processor's target gain in dBFS (clamped to [-96, +24]).
  /// Thread-safe — safe to call from any isolate.
  static void setNativeGainDb(double gainDb) =>
      NativeDspPipeline.instance.setGainDb(gainDb);

  /// Current native gain in dBFS.
  static double get nativeGainDb => NativeDspPipeline.instance.gainDb;

  /// Enable (`true`) or disable (`false`) the gain processor's zero-copy
  /// bypass mode. When bypassed, audio passes through unmodified.
  static void setNativeGainBypass(bool bypass) =>
      NativeDspPipeline.instance.setGainBypass(bypass);

  /// Whether the native gain processor is currently bypassed.
  static bool get nativeGainBypass => NativeDspPipeline.instance.gainBypass;

  /// Enable or disable a specific native DSP processor by its C id
  /// (e.g. `'dsp.gain'`). Thread-safe.
  static void setNativeDspProcessorEnabled(String id,
          {required bool enabled}) =>
      NativeDspPipeline.instance.setProcessorEnabled(id, enabled: enabled);

  /// Whether the named native DSP processor is currently enabled.
  static bool isNativeDspProcessorEnabled(String id) =>
      NativeDspPipeline.instance.isProcessorEnabled(id);

  /// Number of native DSP processors registered in the pipeline.
  static int get nativeDspProcessorCount =>
      NativeDspPipeline.instance.processorCount;

  /// Ids of every registered native DSP processor, in processing order.
  static List<String> get nativeDspProcessorIds => [
        for (var i = 0; i < NativeDspPipeline.instance.processorCount; i++)
          NativeDspPipeline.instance.processorIdAt(i) ?? '',
      ];

  // ── Native DSP: Parametric Equalizer (Phase 5) ───────────────────────────
  //
  // The PEQ processor (dsp.peq) sits immediately after dsp.gain in the
  // pipeline: ExoPlayer PCM → dsp.gain → dsp.peq → AudioTrack.
  // All methods delegate to NativeParametricEq.instance (lock-free, safe
  // to call from any isolate at any time during playback).
  //
  // Usage pattern for a typical Equalizer UI:
  //   1. Subscribe to audioFormatStream to get the current sample rate.
  //   2. On every slider change: call setNativePeqBand(..., sampleRate: sr).
  //   3. If sample rate changes mid-session (track swap), re-apply all bands.
  //   4. Call setNativePeqBypass(true) to A/B compare with flat response.

  /// Whether the native PEQ is available (pipeline initialized on this device).
  static bool get nativePeqAvailable =>
      NativeDspPipeline.instance.isInitialized;

  /// Maximum number of configurable EQ bands (currently 32).
  static int get nativePeqMaxBands =>
      NativeParametricEq.instance.maxBands;

  /// Number of bands that have been configured via [setNativePeqBand].
  static int get nativePeqBandCount =>
      NativeParametricEq.instance.bandCount;

  /// Configure a single EQ band. Coefficients are computed on the calling
  /// thread (control thread) and queued for atomic adoption by the audio
  /// thread — no glitch, no lock held.
  ///
  /// [bandIndex]  : 0 … [nativePeqMaxBands]-1.
  /// [enabled]    : `true` to process this band; `false` to skip (free).
  /// [type]       : Filter topology ([PeqFilterType]).
  /// [freqHz]     : Centre/corner frequency in Hz (clamped internally).
  /// [q]          : Quality factor (typical: 0.5–10). Must be > 0.
  /// [gainDb]     : Boost/cut in dBFS — only used by Peak and Shelf types.
  /// [sampleRate] : Current playback sample rate from [audioFormatStream].
  ///               Pass 0 or omit to fall back to 48 000 Hz.
  ///
  /// Returns the native status code (0 = OK, negative = error).
  static int setNativePeqBand({
    required int bandIndex,
    required bool enabled,
    required PeqFilterType type,
    required double freqHz,
    required double q,
    required double gainDb,
    double sampleRate = 48000.0,
  }) =>
      NativeParametricEq.instance.setBand(
        bandIndex: bandIndex,
        enabled: enabled,
        type: type,
        freqHz: freqHz,
        q: q,
        gainDb: gainDb,
        sampleRate: sampleRate,
      );

  /// Enable or disable a single EQ band without recomputing coefficients.
  /// Useful for quick A/B comparison of individual bands.
  static int setNativePeqBandEnabled(int bandIndex, {required bool enabled}) =>
      NativeParametricEq.instance.setBandEnabled(bandIndex, enabled: enabled);

  /// Whether the band at [bandIndex] is currently enabled.
  static bool isNativePeqBandEnabled(int bandIndex) =>
      NativeParametricEq.instance.isBandEnabled(bandIndex);

  /// Enable (`true`) or disable (`false`) the global PEQ bypass.
  /// When bypassed, the PEQ processor is skipped entirely (zero-copy).
  /// Thread-safe.
  static void setNativePeqBypass(bool bypass) =>
      NativeParametricEq.instance.setBypass(bypass);

  /// Whether the global PEQ bypass is currently active.
  static bool get nativePeqBypass => NativeParametricEq.instance.bypass;

  /// Release native module and DSP pipeline resources. Safe to call even
  /// if never initialized.
  static Future<void> dispose() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    await NativeDspPipeline.instance.dispose();
    await NativeModuleRegistry.disposeAll();
    _initialized = false;
  }

  // ── Native DSP: Dynamics Processing (Phase 6) ────────────────────────────
  //
  // Signal chain (Phase 6): dsp.gain → dsp.peq → dsp.compressor → dsp.limiter
  //                         → dsp.soft_clipper → AudioTrack
  //
  // All methods delegate to the singleton facades in native_audio_runtime.
  // The UI must never import these facades directly — always use PlaybackManager.
  //
  // Sample rate: pass the current value from audioFormatStream to all
  // setParams() calls. If the sample rate changes between tracks, re-apply
  // parameters with the new rate to keep time constants accurate.

  // ── Compressor ──────────────────────────────────────────────────────────

  /// Whether the native compressor is available (pipeline initialized).
  static bool get nativeCompressorAvailable =>
      NativeDspPipeline.instance.isInitialized;

  /// Configure all compressor parameters. Safe to call during playback.
  ///
  /// [thresholdDb]  : Default −20 dBFS. Range (−96, 0).
  /// [ratio]        : Default 4.0. Range [1.001, 100]. 1.0 = no compression.
  /// [attackMs]     : Default 10.0 ms. Range [0.1, 500].
  /// [releaseMs]    : Default 100.0 ms. Range [1, 2000].
  /// [kneeDb]       : Default 6.0 dB. Range [0, 24]. 0 = hard knee.
  /// [makeupGainDb] : Default 0.0 dBFS. Range [−24, 24].
  /// [sampleRate]   : Current playback sample rate. 0 → 48000 Hz fallback.
  static int setNativeCompressorParams({
    double thresholdDb  = -20.0,
    double ratio        =   4.0,
    double attackMs     =  10.0,
    double releaseMs    = 100.0,
    double kneeDb       =   6.0,
    double makeupGainDb =   0.0,
    double sampleRate   = 48000.0,
  }) =>
      NativeCompressor.instance.setParams(
        thresholdDb:  thresholdDb,
        ratio:        ratio,
        attackMs:     attackMs,
        releaseMs:    releaseMs,
        kneeDb:       kneeDb,
        makeupGainDb: makeupGainDb,
        sampleRate:   sampleRate,
      );

  /// Enable (`false`) or bypass (`true`) the compressor.
  static void setNativeCompressorBypass(bool bypass) =>
      NativeCompressor.instance.setBypass(bypass);

  /// Whether the compressor bypass is currently active.
  static bool get nativeCompressorBypass => NativeCompressor.instance.bypass;

  // ── Limiter ─────────────────────────────────────────────────────────────

  /// Whether the native limiter is available (pipeline initialized).
  static bool get nativeLimiterAvailable =>
      NativeDspPipeline.instance.isInitialized;

  /// Configure the limiter. Safe to call during playback.
  ///
  /// [thresholdDb] : Ceiling in dBFS. Default −1.0. Must be < 0.
  /// [releaseMs]   : Gain recovery time in ms. Default 50.0. Range [1, 1000].
  /// [sampleRate]  : Current playback sample rate. 0 → 48000 Hz fallback.
  static int setNativeLimiterParams({
    double thresholdDb = -1.0,
    double releaseMs   = 50.0,
    double sampleRate  = 48000.0,
  }) =>
      NativeLimiter.instance.setParams(
        thresholdDb: thresholdDb,
        releaseMs:   releaseMs,
        sampleRate:  sampleRate,
      );

  /// Enable (`false`) or bypass (`true`) the limiter.
  static void setNativeLimiterBypass(bool bypass) =>
      NativeLimiter.instance.setBypass(bypass);

  /// Whether the limiter bypass is currently active.
  static bool get nativeLimiterBypass => NativeLimiter.instance.bypass;

  /// Look-ahead frames the limiter uses (63 = ~1.3 ms at 48 kHz).
  static int get nativeLimiterLookaheadFrames =>
      NativeLimiter.instance.lookaheadFrames;

  // ── ReplayGain (Phase 8) ──────────────────────────────────────────────────

  /// Whether the native ReplayGain DSP processor is available.
  static bool get nativeReplayGainAvailable =>
      NativeDspPipeline.instance.isInitialized;

  /// Apply a ReplayGain gain value to the native DSP pipeline slot 1.
  ///
  /// [gainDb]                : raw metadata gain in dBFS plus any user preamp
  ///                           offset. Clamped to [−24, +24] by the C layer.
  /// [peakLinear]            : track/album peak in linear scale (e.g. 1.05).
  ///                           Pass 0.0 when no peak data is available.
  /// [useClippingProtection] : when `true` and [peakLinear] > 0, the native
  ///                           layer caps effective gain so that
  ///                           `gain_linear × peak_linear ≤ 1.0`.
  ///
  /// Thread-safe — effective linear gain stored atomically; audio thread picks
  /// it up on its next render cycle without blocking.
  static int setNativeReplayGain({
    required double gainDb,
    double peakLinear = 0.0,
    bool useClippingProtection = true,
  }) =>
      NativeReplayGain.instance.setGain(
        gainDb: gainDb,
        peakLinear: peakLinear,
        useClippingProtection: useClippingProtection,
      );

  /// Bypass (`true`) or engage (`false`) the native ReplayGain DSP processor.
  /// Thread-safe atomic store.
  static void setNativeReplayGainBypass(bool bypass) =>
      NativeReplayGain.instance.setBypass(bypass);

  /// `true` when the native ReplayGain processor is bypassed (gain not applied).
  static bool get nativeReplayGainBypassed => NativeReplayGain.instance.bypass;

  // ── Loudness Normalization (Phase 8.5) ────────────────────────────────────

  /// Whether the native Loudness Normalization DSP processor is available.
  static bool get nativeLoudnessNormAvailable =>
      NativeDspPipeline.instance.isInitialized;

  /// Set the target output loudness in LUFS.
  ///
  /// Typical values: −23.0 (EBU R128 broadcast), −16.0 (podcast), −14.0
  /// (streaming). Clamped to [−36, −6] by the C layer.
  /// Takes effect on the next 85 ms measurement boundary (UPDATE_FRAMES).
  static void setNativeLoudnessNormTargetLufs(double lufs) =>
      NativeLoudnessNorm.instance.setTargetLufs(lufs);

  /// Bypass (`true`) or engage (`false`) the Loudness Normalization processor.
  /// Thread-safe atomic store.
  static void setNativeLoudnessNormBypass(bool bypass) =>
      NativeLoudnessNorm.instance.setBypass(bypass);

  /// `true` when the Loudness Normalization processor is bypassed.
  static bool get nativeLoudnessNormBypassed =>
      NativeLoudnessNorm.instance.bypass;

  /// Update the K-weighting coefficients for a new sample rate.
  /// Call when ExoPlayer reports a sample-rate change between tracks.
  static void setNativeLoudnessSampleRate(int sampleRate) =>
      NativeLoudnessNorm.instance.setSampleRate(sampleRate);

  /// Current short-term LUFS reading from the analyzer.
  /// Returns −99.0 before the first 85 ms window completes or when bypassed.
  static double get nativeLoudnessMeasuredLufs =>
      NativeLoudnessNorm.instance.measuredLufs;

  /// Current smooth gain applied to the audio stream, in dBFS.
  /// Positive = boost, negative = attenuation. 0.0 when bypassed.
  static double get nativeLoudnessAppliedGainDb =>
      NativeLoudnessNorm.instance.appliedGainDb;

  /// Reset the loudness analyzer and smooth gain back to unity.
  /// Must be called on every track change so each track is measured fresh.
  static void resetNativeLoudnessNorm() => NativeLoudnessNorm.instance.reset();

  // ── Soft Clipper ────────────────────────────────────────────────────────

  /// Whether the native soft clipper is available (pipeline initialized).
  static bool get nativeSoftClipperAvailable =>
      NativeDspPipeline.instance.isInitialized;

  /// Set the soft-clip threshold in dBFS. Default: −0.5 dBFS.
  /// Samples below the threshold pass through unchanged; samples above are
  /// shaped toward 0 dBFS via a tanh curve. Range: [−12, −0.001).
  static void setNativeSoftClipperThresholdDb(double thresholdDb) =>
      NativeSoftClipper.instance.setThresholdDb(thresholdDb);

  /// Current soft-clip threshold in dBFS.
  static double get nativeSoftClipperThresholdDb =>
      NativeSoftClipper.instance.thresholdDb;

  /// Enable (`false`) or bypass (`true`) the soft clipper.
  static void setNativeSoftClipperBypass(bool bypass) =>
      NativeSoftClipper.instance.setBypass(bypass);

  /// Whether the soft clipper bypass is currently active.
  static bool get nativeSoftClipperBypass => NativeSoftClipper.instance.bypass;

  // ── Native DSP: Crossfeed / Stereo Processing (Phase 7) ──────────────────
  //
  // Signal chain (Phase 7): dsp.gain → dsp.peq → dsp.compressor →
  //                          dsp.crossfeed → dsp.limiter → dsp.soft_clipper
  //
  // Crossfeed improves headphone listening by blending a lowpass-filtered
  // version of each channel into the opposite channel, reducing the unnatural
  // channel isolation of headphones and reproducing the acoustic coupling of
  // speakers. Only the L and R channels are affected; mono/surround channels
  // pass through unchanged.
  //
  // All methods delegate directly to [NativeCrossfeed.instance]. The UI must
  // not import that class — use only these PlaybackManager statics.

  /// Whether the crossfeed processor is available on this device.
  /// `true` on Android (native FFI active); `false` on web/unsupported.
  static bool get nativeCrossfeedAvailable =>
      NativeDspPipeline.instance.isInitialized;

  /// Configure all crossfeed parameters in one call.
  ///
  /// Parameters are pre-computed on the calling thread (biquad coefficient
  /// computation via sinf/cosf) and adopted lock-free by the audio thread on
  /// its next render cycle — no audible interruption.
  ///
  /// [amount]    : Crossfeed blend [0, 1]. Default 0.3. 0 = off.
  /// [cutoffHz]  : LP cutoff for cross path [100, 2000] Hz. Default 700.
  /// [hfCompDb]  : HF shelf gain [0, 12] dB. Default 3.0.
  /// [hfCompHz]  : HF shelf corner [1000, 16000] Hz. Default 4000.
  /// [width]     : Stereo width after mixing [0, 2]. Default 1.0.
  /// [sampleRate]: Current playback sample rate. 0 → 48000 Hz fallback.
  static int setNativeCrossfeedParams({
    double amount = 0.3,
    double cutoffHz = 700.0,
    double hfCompDb = 3.0,
    double hfCompHz = 4000.0,
    double width = 1.0,
    double sampleRate = 48000.0,
  }) =>
      NativeCrossfeed.instance.setParams(
        amount: amount,
        cutoffHz: cutoffHz,
        hfCompDb: hfCompDb,
        hfCompHz: hfCompHz,
        width: width,
        sampleRate: sampleRate,
      );

  /// Enable (`false`) or bypass (`true`) the crossfeed processor.
  /// Thread-safe — may be called while audio is rendering.
  static void setNativeCrossfeedBypass(bool bypass) =>
      NativeCrossfeed.instance.setBypass(bypass);

  /// Whether the crossfeed bypass is currently active.
  static bool get nativeCrossfeedBypass => NativeCrossfeed.instance.bypass;

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
