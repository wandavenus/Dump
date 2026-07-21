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

// ── playback_manager.dart — split plan ───────────────────────────────────────
//
// Sections extracted to part files under playback_manager/:
//   transport.dart        — Transport, Mode, Playback parameters, Queue mutations
//   dsp_media3.dart       — DSP effects (Media3), Capabilities, Audio format,
//                           Sleep timer, State snapshot, Native module access,
//                           FFmpeg decoder (Phase 9)
//   native_dsp.dart       — Native DSP pipeline (Phase 4–8.5): fail-open guard,
//                           Gain, Compressor, Limiter, ReplayGain, Loudness Norm,
//                           Soft Clipper, Crossfeed, dispose()
//   artwork_prefetch.dart — _prefetchArtwork() private helper
//
// This file retains: imports, part directives, EqualizerParameters type,
// class declaration, fields, public streams, and initialize().

part 'playback_manager/transport.dart';
part 'playback_manager/dsp_media3.dart';
part 'playback_manager/native_dsp.dart';
part 'playback_manager/artwork_prefetch.dart';

// ─── Equalizer parameter type ─────────────────────────────────────────────────

class EqualizerParameters {
  final double minDecibels;
  final double maxDecibels;
  final int bandCount;

  /// Center frequency (Hz) of each band, in band order. May be shorter than
  /// [bandCount] or empty when the engine did not report frequencies (e.g.
  /// before the first audio session) — callers should fall back to a
  /// standard 5-band frequency set in that case.
  final List<int> centerFrequenciesHz;

  const EqualizerParameters({
    required this.minDecibels,
    required this.maxDecibels,
    required this.bandCount,
    this.centerFrequenciesHz = const [],
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
}
