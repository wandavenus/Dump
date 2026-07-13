// Runs the REAL native runtime, compiled for the host platform by the
// native-assets build hook (`hook/build.dart`) when this test executes.
//
// Phase 4 additions: DSP pipeline init, gain processor registration,
// buffer processing (unity gain / non-zero gain / bypass), enable/disable.
//
// Phase 5 additions: PEQ processor registration, band configuration.
//
// Phase 6 additions: Compressor, Limiter, SoftClipper registration and
// functional verification (gain reduction, brickwall ceiling, tanh waveshaper).
//
// Note on local execution: `native_toolchain_c` resolves to `clang` on PATH.
// This container only has `gcc`. A throwaway symlink works around it:
//   ln -s $(which gcc) /tmp/clang && PATH=/tmp:$PATH dart test
// This is a local verification workaround only — Android NDK provides its
// own clang, so this is not a project or CI requirement.
import 'dart:async';
import 'dart:math' as math;

import 'package:native_audio_runtime/native_audio_runtime.dart';
import 'package:test/test.dart';

void main() {
  // Best-effort teardown: dispose pipeline before runtime so the pipeline
  // can call dispose() on its processors while the runtime is still valid.
  tearDown(() async {
    await NativeDspPipeline.instance.dispose();
    await NativeAudioRuntime.instance.dispose();
  });

  // ── NativeAudioRuntime tests (Phase 3 — unchanged) ───────────────────────

  test('reports availability', () {
    expect(NativeAudioRuntime.instance, isNotNull);
  });

  test('initialize is idempotent and sets isAvailable', () async {
    await NativeAudioRuntime.instance.initialize();
    expect(NativeAudioRuntime.instance.isAvailable, isTrue);

    await NativeAudioRuntime.instance.initialize();
    expect(NativeAudioRuntime.instance.isAvailable, isTrue);
  });

  test('version is a non-empty string', () async {
    await NativeAudioRuntime.instance.initialize();
    expect(NativeAudioRuntime.instance.version, isNotEmpty);
    expect(NativeAudioRuntime.instance.version, isNot('unknown'));
  });

  test('capabilities include Phase 4–6 processors as supported; '
      'future placeholders remain unsupported', () async {
    await NativeAudioRuntime.instance.initialize();
    final caps = NativeAudioRuntime.instance.capabilities;
    expect(caps, isNotEmpty);

    // Phase 4 / 4.5 — always supported
    final supportedKeys = [
      'dsp.pipeline',
      'dsp.gain',
      'dsp.media3_integration',
      // Phase 5
      'dsp.equalizer',
      // Phase 6
      'dsp.compressor',
      'dsp.limiter',
      'dsp.soft_clipper',
      // Phase 7
      'dsp.crossfeed',
      // Phase 8
      'dsp.replaygain',
    ];
    for (final key in supportedKeys) {
      final cap = caps.firstWhere(
        (c) => c.key == key,
        orElse: () => throw TestFailure('capability $key not found'),
      );
      expect(cap.supported, isTrue, reason: '$key must be supported');
    }

    // Everything else is a placeholder (supported = false).
    final unsupportedKeys = [
      'dsp.bass_boost',
      'dsp.virtualizer',
      'dsp.resampler',
      'decoder.flac_hires',
      'decoder.dsd',
      'scan.loudness_ebur128',
    ];
    for (final key in unsupportedKeys) {
      final cap = caps.firstWhere(
        (c) => c.key == key,
        orElse: () => NativeRuntimeCapability(key: key, supported: false),
      );
      expect(cap.supported, isFalse, reason: '$key must remain unsupported');
    }
  });

  test('registerModule succeeds once, then reports duplicate', () async {
    await NativeAudioRuntime.instance.initialize();
    final first = NativeAudioRuntime.instance.registerModule('native_dsp');
    expect(first, NativeRuntimeStatus.ok);

    final second = NativeAudioRuntime.instance.registerModule('native_dsp');
    expect(second, NativeRuntimeStatus.duplicateModule);

    expect(
      NativeAudioRuntime.instance.registeredModuleIds,
      contains('native_dsp'),
    );
  });

  test('registerModule before initialize reports notInitialized', () async {
    await NativeAudioRuntime.instance.dispose();
    final status = NativeAudioRuntime.instance.registerModule(
      'too_early_module',
    );
    expect(status, NativeRuntimeStatus.notInitialized);
  });

  test(
    'concurrent initialize calls are safe (thread-safety contract)',
    () async {
      final futures = <Future<void>>[
        for (var i = 0; i < 8; i++) NativeAudioRuntime.instance.initialize(),
      ];
      await Future.wait(futures);
      expect(NativeAudioRuntime.instance.isAvailable, isTrue);
    },
  );

  test('dispose is safe without a prior initialize', () async {
    await NativeAudioRuntime.instance.dispose();
    await NativeAudioRuntime.instance.dispose();
  });

  // ── NativeDspPipeline tests (Phase 4) ────────────────────────────────────

  test('DSP pipeline initializes after runtime', () async {
    await NativeAudioRuntime.instance.initialize();
    await NativeDspPipeline.instance.initialize();
    expect(NativeDspPipeline.instance.isInitialized, isTrue);
  });

  test('DSP pipeline initialization is idempotent', () async {
    await NativeAudioRuntime.instance.initialize();
    await NativeDspPipeline.instance.initialize();
    await NativeDspPipeline.instance
        .initialize(); // second call — must not throw
    expect(NativeDspPipeline.instance.isInitialized, isTrue);
  });

  test('pipeline registers all 8 processors (Phase 4–8.5) in order', () async {
    await NativeAudioRuntime.instance.initialize();
    await NativeDspPipeline.instance.initialize();

    // [0]gain → [1]replaygain → [2]loudness → [3]peq → [4]compressor →
    // [5]crossfeed → [6]limiter → [7]soft_clipper
    expect(NativeDspPipeline.instance.processorCount, equals(8));
    expect(NativeDspPipeline.instance.processorIdAt(0), equals('dsp.gain'));
    expect(
      NativeDspPipeline.instance.processorIdAt(1),
      equals('dsp.replaygain'),
    );
    expect(NativeDspPipeline.instance.processorIdAt(2), equals('dsp.loudness'));
    expect(NativeDspPipeline.instance.processorIdAt(3), equals('dsp.peq'));
    expect(
      NativeDspPipeline.instance.processorIdAt(4),
      equals('dsp.compressor'),
    );
    expect(
      NativeDspPipeline.instance.processorIdAt(5),
      equals('dsp.crossfeed'),
    );
    expect(NativeDspPipeline.instance.processorIdAt(6), equals('dsp.limiter'));
    expect(
      NativeDspPipeline.instance.processorIdAt(7),
      equals('dsp.soft_clipper'),
    );
  });

  test('gain processor defaults to 0 dBFS and bypass off', () async {
    await NativeAudioRuntime.instance.initialize();
    await NativeDspPipeline.instance.initialize();
    expect(NativeDspPipeline.instance.gainDb, closeTo(0.0, 0.001));
    expect(NativeDspPipeline.instance.gainBypass, isFalse);
  });

  test('gain processor gain clamps to valid range', () async {
    await NativeAudioRuntime.instance.initialize();
    await NativeDspPipeline.instance.initialize();

    NativeDspPipeline.instance.setGainDb(999.0);
    expect(NativeDspPipeline.instance.gainDb, closeTo(24.0, 0.001));

    NativeDspPipeline.instance.setGainDb(-999.0);
    expect(NativeDspPipeline.instance.gainDb, closeTo(-96.0, 0.001));
  });

  test('gain processor unity gain leaves buffer unchanged', () async {
    await NativeAudioRuntime.instance.initialize();
    await NativeDspPipeline.instance.initialize();

    // Unity gain (0 dBFS) + all other processors bypassed so only gain matters.
    NativeDspPipeline.instance.setGainDb(0.0);
    NativeDspPipeline.instance.setGainBypass(false);
    NativeLoudnessNorm.instance.setBypass(true);
    NativeCrossfeed.instance.setBypass(true);
    NativeCompressor.instance.setBypass(true);
    NativeLimiter.instance.setBypass(true);
    NativeSoftClipper.instance.setBypass(true);

    final buf = NativeAudioBuffer.create(
      capacityFrames: 4,
      channelCount: 2,
      sampleRate: 44100,
    );
    expect(buf, isNotNull, reason: 'buffer allocation must succeed');
    buf!;

    try {
      final data = buf.data;
      for (var i = 0; i < data.length; i++) {
        data[i] = 0.5;
      }

      final result = NativeDspPipeline.instance.processBuffer(buf);
      expect(result, equals(0)); // NATIVE_RUNTIME_OK

      for (var i = 0; i < buf.data.length; i++) {
        expect(
          buf.data[i],
          closeTo(0.5, 1e-5),
          reason: 'unity gain must not change samples',
        );
      }
    } finally {
      buf.destroy();
    }
  });

  test('gain processor applies +6 dBFS gain correctly', () async {
    await NativeAudioRuntime.instance.initialize();
    await NativeDspPipeline.instance.initialize();

    const gainDb = 6.0;
    final expectedLinear = math.pow(10.0, gainDb / 20.0); // ≈ 1.9953
    NativeDspPipeline.instance.setGainDb(gainDb);
    NativeDspPipeline.instance.setGainBypass(false);
    // Bypass all other processors so only gain is active.
    NativeLoudnessNorm.instance.setBypass(true);
    NativeCrossfeed.instance.setBypass(true);
    NativeCompressor.instance.setBypass(true);
    NativeLimiter.instance.setBypass(true);
    NativeSoftClipper.instance.setBypass(true);

    final buf = NativeAudioBuffer.create(
      capacityFrames: 8,
      channelCount: 1,
      sampleRate: 48000,
    );
    expect(buf, isNotNull);
    buf!;

    try {
      final data = buf.data;
      for (var i = 0; i < data.length; i++) {
        data[i] = 1.0;
      }

      NativeDspPipeline.instance.processBuffer(buf);

      for (var i = 0; i < buf.data.length; i++) {
        expect(
          buf.data[i],
          closeTo(expectedLinear, 1e-4),
          reason: '+6 dBFS on 1.0 must yield ~1.9953',
        );
      }
    } finally {
      buf.destroy();
    }
  });

  test('gain processor bypass is true zero-copy', () async {
    await NativeAudioRuntime.instance.initialize();
    await NativeDspPipeline.instance.initialize();

    NativeDspPipeline.instance.setGainDb(
      20.0,
    ); // high gain — would change samples
    NativeDspPipeline.instance.setGainBypass(true); // but bypass on
    NativeLoudnessNorm.instance.setBypass(true);
    NativeCrossfeed.instance.setBypass(true);
    NativeCompressor.instance.setBypass(true);
    NativeLimiter.instance.setBypass(true);
    NativeSoftClipper.instance.setBypass(true);

    final buf = NativeAudioBuffer.create(
      capacityFrames: 4,
      channelCount: 2,
      sampleRate: 44100,
    );
    expect(buf, isNotNull);
    buf!;

    try {
      final data = buf.data;
      for (var i = 0; i < data.length; i++) {
        data[i] = 0.7;
      }

      NativeDspPipeline.instance.processBuffer(buf);

      for (var i = 0; i < buf.data.length; i++) {
        expect(
          buf.data[i],
          closeTo(0.7, 1e-6),
          reason: 'bypass must leave samples untouched',
        );
      }
    } finally {
      buf.destroy();
    }
  });

  test('pipeline enable/disable skips processor entirely', () async {
    await NativeAudioRuntime.instance.initialize();
    await NativeDspPipeline.instance.initialize();

    NativeDspPipeline.instance.setGainDb(
      20.0,
    ); // would change samples if applied
    NativeDspPipeline.instance.setGainBypass(false);
    NativeDspPipeline.instance.setProcessorEnabled('dsp.gain', enabled: false);
    expect(NativeDspPipeline.instance.isProcessorEnabled('dsp.gain'), isFalse);

    // Bypass dynamics so they don't interfere with the gain isolation test.
    NativeLoudnessNorm.instance.setBypass(true);
    NativeCrossfeed.instance.setBypass(true);
    NativeCompressor.instance.setBypass(true);
    NativeLimiter.instance.setBypass(true);
    NativeSoftClipper.instance.setBypass(true);

    final buf = NativeAudioBuffer.create(
      capacityFrames: 4,
      channelCount: 1,
      sampleRate: 44100,
    );
    expect(buf, isNotNull);
    buf!;

    try {
      final data = buf.data;
      for (var i = 0; i < data.length; i++) {
        data[i] = 0.3;
      }

      NativeDspPipeline.instance.processBuffer(buf);

      for (var i = 0; i < buf.data.length; i++) {
        expect(
          buf.data[i],
          closeTo(0.3, 1e-6),
          reason: 'disabled processor must not touch samples',
        );
      }

      // Re-enable and verify gain is applied.
      NativeDspPipeline.instance.setProcessorEnabled('dsp.gain', enabled: true);
      expect(NativeDspPipeline.instance.isProcessorEnabled('dsp.gain'), isTrue);
      NativeDspPipeline.instance.processBuffer(buf);

      final expectedLinear = math.pow(10.0, 20.0 / 20.0); // 10×
      for (var i = 0; i < buf.data.length; i++) {
        expect(
          buf.data[i],
          closeTo(0.3 * expectedLinear, 1e-4),
          reason: 're-enabled processor must apply gain',
        );
      }
    } finally {
      buf.destroy();
    }
  });

  test('pipeline reset does not throw', () async {
    await NativeAudioRuntime.instance.initialize();
    await NativeDspPipeline.instance.initialize();
    expect(() => NativeDspPipeline.instance.reset(), returnsNormally);
  });

  test(
    'pipeline total latency equals limiter look-ahead (63 frames)',
    () async {
      // Phase 6: the limiter introduces NAR_LIMITER_LOOKAHEAD_FRAMES − 1 = 63
      // frames of algorithmic latency. All other processors are zero-latency.
      await NativeAudioRuntime.instance.initialize();
      await NativeDspPipeline.instance.initialize();
      expect(NativeDspPipeline.instance.totalLatencyFrames, equals(63));
    },
  );

  test('NativeAudioBuffer metadata is correct', () async {
    await NativeAudioRuntime.instance.initialize();

    final buf = NativeAudioBuffer.create(
      capacityFrames: 16,
      channelCount: 2,
      sampleRate: 48000,
    );
    expect(buf, isNotNull);
    buf!;

    try {
      expect(buf.capacityFrames, equals(16));
      expect(buf.frameCount, equals(16)); // starts full
      expect(buf.channelCount, equals(2));
      expect(buf.sampleRate, equals(48000));
      expect(buf.data.length, equals(32)); // 16 frames × 2 channels

      expect(buf.setFrameCount(8), equals(0)); // OK
      expect(buf.frameCount, equals(8));
    } finally {
      buf.destroy();
    }
  });

  test('NativeAudioBuffer timestamp round-trips', () async {
    await NativeAudioRuntime.instance.initialize();

    final buf = NativeAudioBuffer.create(
      capacityFrames: 4,
      channelCount: 1,
      sampleRate: 44100,
    );
    expect(buf, isNotNull);
    buf!;

    try {
      buf.setTimestampUs(1234567890);
      expect(buf.timestampUs, equals(1234567890));
    } finally {
      buf.destroy();
    }
  });

  test('NativeAudioBuffer.create returns null for invalid args', () async {
    await NativeAudioRuntime.instance.initialize();
    expect(
      NativeAudioBuffer.create(
        capacityFrames: -1,
        channelCount: 2,
        sampleRate: 44100,
      ),
      isNull,
    );
    expect(
      NativeAudioBuffer.create(
        capacityFrames: 16,
        channelCount: 0,
        sampleRate: 44100,
      ),
      isNull,
    );
  });

  test('pipeline dispose is safe to call without prior initialize', () async {
    // NativeDspPipeline.instance starts un-initialized — dispose must be no-op.
    await NativeDspPipeline.instance.dispose();
    expect(NativeDspPipeline.instance.isInitialized, isFalse);
  });

  // ── NativeCompressor tests (Phase 6) ─────────────────────────────────────

  test('compressor: default bypass is off', () async {
    await NativeAudioRuntime.instance.initialize();
    await NativeDspPipeline.instance.initialize();
    expect(NativeCompressor.instance.bypass, isFalse);
  });

  test('compressor: bypass round-trips correctly', () async {
    await NativeAudioRuntime.instance.initialize();
    await NativeDspPipeline.instance.initialize();

    NativeCompressor.instance.setBypass(true);
    expect(NativeCompressor.instance.bypass, isTrue);

    NativeCompressor.instance.setBypass(false);
    expect(NativeCompressor.instance.bypass, isFalse);
  });

  test('compressor: bypass passes audio unchanged', () async {
    await NativeAudioRuntime.instance.initialize();
    await NativeDspPipeline.instance.initialize();

    // Isolate: only run the compressor
    NativeDspPipeline.instance.setProcessorEnabled('dsp.gain', enabled: false);
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.replaygain',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.loudness',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled('dsp.peq', enabled: false);
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.replaygain',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.loudness',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.crossfeed',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.limiter',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.soft_clipper',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.compressor',
      enabled: true,
    );
    NativeCompressor.instance.setBypass(true);

    final buf = NativeAudioBuffer.create(
      capacityFrames: 16,
      channelCount: 2,
      sampleRate: 48000,
    );
    expect(buf, isNotNull);
    buf!;

    try {
      for (var i = 0; i < buf.data.length; i++) {
        buf.data[i] = 0.8;
      }

      NativeDspPipeline.instance.processBuffer(buf);

      for (var i = 0; i < buf.data.length; i++) {
        expect(
          buf.data[i],
          closeTo(0.8, 1e-6),
          reason: 'compressor bypass must leave samples untouched',
        );
      }
    } finally {
      buf.destroy();
    }
  });

  test('compressor: reduces gain on signals above threshold', () async {
    await NativeAudioRuntime.instance.initialize();
    await NativeDspPipeline.instance.initialize();

    // Isolate: only run the compressor
    NativeDspPipeline.instance.setProcessorEnabled('dsp.gain', enabled: false);
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.replaygain',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.loudness',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled('dsp.peq', enabled: false);
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.replaygain',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.loudness',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.crossfeed',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.limiter',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.soft_clipper',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.compressor',
      enabled: true,
    );
    NativeCompressor.instance.setBypass(false);

    // High-ratio compressor with low threshold and instant attack (0 ms).
    // The signal at 0.8 linear ≈ −1.94 dBFS is well above the −30 dBFS
    // threshold, so it must come out significantly reduced.
    NativeCompressor.instance.setParams(
      thresholdDb: -30.0,
      ratio: 10.0,
      attackMs: 0.1, // near-instant
      releaseMs: 200.0,
      kneeDb: 0.0, // hard knee
      makeupGainDb: 0.0,
      sampleRate: 48000.0,
    );

    final buf = NativeAudioBuffer.create(
      capacityFrames: 128,
      channelCount: 1,
      sampleRate: 48000,
    );
    expect(buf, isNotNull);
    buf!;

    try {
      // Fill with a signal well above the threshold.
      for (var i = 0; i < buf.data.length; i++) {
        buf.data[i] = 0.8; // ≈ −1.94 dBFS, far above −30 dBFS threshold
      }

      NativeDspPipeline.instance.processBuffer(buf);

      // With 10:1 ratio and no makeup, output must be substantially lower.
      // Exact value depends on envelope timing, so just verify reduction.
      // We check the last frame (envelope fully engaged after 128 frames).
      final lastSample = buf.data[buf.data.length - 1];
      expect(
        lastSample,
        lessThan(0.8),
        reason: 'compressor must reduce gain above threshold',
      );
      // Must still be positive (gain only ever attenuates)
      expect(lastSample, greaterThan(0.0));
    } finally {
      buf.destroy();
    }
  });

  test('compressor: signals below threshold pass through unmodified', () async {
    await NativeAudioRuntime.instance.initialize();
    await NativeDspPipeline.instance.initialize();

    // Isolate compressor
    NativeDspPipeline.instance.setProcessorEnabled('dsp.gain', enabled: false);
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.replaygain',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.loudness',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled('dsp.peq', enabled: false);
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.replaygain',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.loudness',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.crossfeed',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.limiter',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.soft_clipper',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.compressor',
      enabled: true,
    );
    NativeCompressor.instance.setBypass(false);

    // Threshold far above signal: −3 dBFS threshold, signal at 0.01 (−40 dBFS)
    NativeCompressor.instance.setParams(
      thresholdDb: -3.0,
      ratio: 8.0,
      attackMs: 1.0,
      releaseMs: 100.0,
      kneeDb: 0.0,
      makeupGainDb: 0.0,
      sampleRate: 48000.0,
    );

    final buf = NativeAudioBuffer.create(
      capacityFrames: 32,
      channelCount: 1,
      sampleRate: 48000,
    );
    expect(buf, isNotNull);
    buf!;

    try {
      for (var i = 0; i < buf.data.length; i++) {
        buf.data[i] = 0.01; // −40 dBFS — well below −3 dBFS threshold
      }

      NativeDspPipeline.instance.processBuffer(buf);

      for (var i = 0; i < buf.data.length; i++) {
        expect(
          buf.data[i],
          closeTo(0.01, 1e-5),
          reason: 'signal below threshold must not be compressed',
        );
      }
    } finally {
      buf.destroy();
    }
  });

  test('compressor: setParams returns NATIVE_RUNTIME_OK (0)', () async {
    await NativeAudioRuntime.instance.initialize();
    await NativeDspPipeline.instance.initialize();

    final status = NativeCompressor.instance.setParams(
      thresholdDb: -20.0,
      ratio: 4.0,
      attackMs: 10.0,
      releaseMs: 100.0,
      kneeDb: 6.0,
      makeupGainDb: 0.0,
      sampleRate: 48000.0,
    );
    expect(status, equals(0)); // NATIVE_RUNTIME_OK
  });

  // ── NativeLimiter tests (Phase 6) ─────────────────────────────────────────

  test('limiter: default bypass is off', () async {
    await NativeAudioRuntime.instance.initialize();
    await NativeDspPipeline.instance.initialize();
    expect(NativeLimiter.instance.bypass, isFalse);
  });

  test('limiter: bypass round-trips correctly', () async {
    await NativeAudioRuntime.instance.initialize();
    await NativeDspPipeline.instance.initialize();

    NativeLimiter.instance.setBypass(true);
    expect(NativeLimiter.instance.bypass, isTrue);

    NativeLimiter.instance.setBypass(false);
    expect(NativeLimiter.instance.bypass, isFalse);
  });

  test('limiter: look-ahead frames is 63', () async {
    await NativeAudioRuntime.instance.initialize();
    await NativeDspPipeline.instance.initialize();
    // NAR_LIMITER_LOOKAHEAD_FRAMES − 1 = 64 − 1 = 63
    expect(NativeLimiter.instance.lookaheadFrames, equals(63));
  });

  test(
    'limiter: bypass passes audio unchanged (look-ahead delay not active)',
    () async {
      await NativeAudioRuntime.instance.initialize();
      await NativeDspPipeline.instance.initialize();

      // Isolate: only the limiter
      NativeDspPipeline.instance.setProcessorEnabled(
        'dsp.gain',
        enabled: false,
      );
      NativeDspPipeline.instance.setProcessorEnabled(
        'dsp.replaygain',
        enabled: false,
      );
      NativeDspPipeline.instance.setProcessorEnabled(
        'dsp.loudness',
        enabled: false,
      );
      NativeDspPipeline.instance.setProcessorEnabled('dsp.peq', enabled: false);
      NativeDspPipeline.instance.setProcessorEnabled(
        'dsp.compressor',
        enabled: false,
      );
      NativeDspPipeline.instance.setProcessorEnabled(
        'dsp.soft_clipper',
        enabled: false,
      );
      NativeDspPipeline.instance.setProcessorEnabled(
        'dsp.replaygain',
        enabled: false,
      );
      NativeDspPipeline.instance.setProcessorEnabled(
        'dsp.loudness',
        enabled: false,
      );
      NativeDspPipeline.instance.setProcessorEnabled(
        'dsp.crossfeed',
        enabled: false,
      );
      NativeDspPipeline.instance.setProcessorEnabled(
        'dsp.limiter',
        enabled: true,
      );
      NativeLimiter.instance.setBypass(true);

      final buf = NativeAudioBuffer.create(
        capacityFrames: 16,
        channelCount: 2,
        sampleRate: 48000,
      );
      expect(buf, isNotNull);
      buf!;

      try {
        for (var i = 0; i < buf.data.length; i++) {
          buf.data[i] = 0.9;
        }

        NativeDspPipeline.instance.processBuffer(buf);

        for (var i = 0; i < buf.data.length; i++) {
          expect(
            buf.data[i],
            closeTo(0.9, 1e-6),
            reason: 'limiter bypass must leave samples untouched',
          );
        }
      } finally {
        buf.destroy();
      }
    },
  );

  test('limiter: prevents output from exceeding threshold (brickwall)', () async {
    await NativeAudioRuntime.instance.initialize();
    await NativeDspPipeline.instance.initialize();

    // Isolate the limiter
    NativeDspPipeline.instance.setProcessorEnabled('dsp.gain', enabled: false);
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.replaygain',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.loudness',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled('dsp.peq', enabled: false);
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.compressor',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.soft_clipper',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.limiter',
      enabled: true,
    );
    NativeLimiter.instance.setBypass(false);

    // Threshold: −6 dBFS ≈ 0.5012 linear
    NativeLimiter.instance.setParams(
      thresholdDb: -6.0,
      releaseMs: 100.0,
      sampleRate: 48000.0,
    );

    // Use a large buffer so the look-ahead is fully engaged (64+ frames).
    // Input signal is 0.9 linear (0 dBFS = −0.9 dB), well above −6 dBFS.
    // After the 63-frame look-ahead primes, the output MUST NOT exceed the threshold.
    final bufSize = 256;
    final buf = NativeAudioBuffer.create(
      capacityFrames: bufSize,
      channelCount: 1,
      sampleRate: 48000,
    );
    expect(buf, isNotNull);
    buf!;

    final thresholdLinear = math.pow(10.0, -6.0 / 20.0); // ≈ 0.5012

    try {
      for (var i = 0; i < buf.data.length; i++) {
        buf.data[i] = 0.9; // well above threshold
      }

      NativeDspPipeline.instance.processBuffer(buf);

      // After the look-ahead primes (frame 63 onward), the gain should be
      // fully engaged. Check the second half of the buffer (frames 128–255).
      for (var i = bufSize ~/ 2; i < buf.data.length; i++) {
        expect(
          buf.data[i],
          lessThanOrEqualTo(thresholdLinear + 1e-5),
          reason:
              'limiter must enforce brickwall ceiling at ${thresholdLinear.toStringAsFixed(4)}',
        );
        expect(
          buf.data[i],
          greaterThanOrEqualTo(0.0),
          reason: 'limiter must not produce negative output for positive input',
        );
      }
    } finally {
      buf.destroy();
    }
  });

  test('limiter: setParams returns NATIVE_RUNTIME_OK (0)', () async {
    await NativeAudioRuntime.instance.initialize();
    await NativeDspPipeline.instance.initialize();

    final status = NativeLimiter.instance.setParams(
      thresholdDb: -1.0,
      releaseMs: 50.0,
      sampleRate: 48000.0,
    );
    expect(status, equals(0));
  });

  // ── NativeSoftClipper tests (Phase 6) ────────────────────────────────────

  test('soft clipper: default bypass is off', () async {
    await NativeAudioRuntime.instance.initialize();
    await NativeDspPipeline.instance.initialize();
    expect(NativeSoftClipper.instance.bypass, isFalse);
  });

  test('soft clipper: bypass round-trips correctly', () async {
    await NativeAudioRuntime.instance.initialize();
    await NativeDspPipeline.instance.initialize();

    NativeSoftClipper.instance.setBypass(true);
    expect(NativeSoftClipper.instance.bypass, isTrue);

    NativeSoftClipper.instance.setBypass(false);
    expect(NativeSoftClipper.instance.bypass, isFalse);
  });

  test('soft clipper: threshold round-trips and is clamped', () async {
    await NativeAudioRuntime.instance.initialize();
    await NativeDspPipeline.instance.initialize();

    NativeSoftClipper.instance.setThresholdDb(-3.0);
    expect(NativeSoftClipper.instance.thresholdDb, closeTo(-3.0, 0.001));

    // Clamp at upper bound (−0.001)
    NativeSoftClipper.instance.setThresholdDb(0.0);
    expect(NativeSoftClipper.instance.thresholdDb, lessThan(0.0));

    // Clamp at lower bound (−12.0)
    NativeSoftClipper.instance.setThresholdDb(-999.0);
    expect(NativeSoftClipper.instance.thresholdDb, closeTo(-12.0, 0.001));
  });

  test(
    'soft clipper: signals below threshold pass through unchanged',
    () async {
      await NativeAudioRuntime.instance.initialize();
      await NativeDspPipeline.instance.initialize();

      // Isolate the soft clipper
      NativeDspPipeline.instance.setProcessorEnabled(
        'dsp.gain',
        enabled: false,
      );
      NativeDspPipeline.instance.setProcessorEnabled(
        'dsp.replaygain',
        enabled: false,
      );
      NativeDspPipeline.instance.setProcessorEnabled(
        'dsp.loudness',
        enabled: false,
      );
      NativeDspPipeline.instance.setProcessorEnabled('dsp.peq', enabled: false);
      NativeDspPipeline.instance.setProcessorEnabled(
        'dsp.compressor',
        enabled: false,
      );
      NativeDspPipeline.instance.setProcessorEnabled(
        'dsp.crossfeed',
        enabled: false,
      );
      NativeDspPipeline.instance.setProcessorEnabled(
        'dsp.crossfeed',
        enabled: false,
      );
      NativeDspPipeline.instance.setProcessorEnabled(
        'dsp.limiter',
        enabled: false,
      );
      NativeDspPipeline.instance.setProcessorEnabled(
        'dsp.soft_clipper',
        enabled: true,
      );
      NativeSoftClipper.instance.setBypass(false);

      // Threshold: −6 dBFS ≈ 0.5012. Signal at 0.3 — well below threshold.
      NativeSoftClipper.instance.setThresholdDb(-6.0);

      final buf = NativeAudioBuffer.create(
        capacityFrames: 32,
        channelCount: 2,
        sampleRate: 48000,
      );
      expect(buf, isNotNull);
      buf!;

      try {
        for (var i = 0; i < buf.data.length; i++) {
          buf.data[i] = 0.3; // below −6 dBFS threshold
        }

        NativeDspPipeline.instance.processBuffer(buf);

        for (var i = 0; i < buf.data.length; i++) {
          expect(
            buf.data[i],
            closeTo(0.3, 1e-6),
            reason: 'signal below threshold must pass through unmodified',
          );
        }
      } finally {
        buf.destroy();
      }
    },
  );

  test(
    'soft clipper: shapes samples above threshold and stays below 0 dBFS',
    () async {
      await NativeAudioRuntime.instance.initialize();
      await NativeDspPipeline.instance.initialize();

      // Isolate the soft clipper
      NativeDspPipeline.instance.setProcessorEnabled(
        'dsp.gain',
        enabled: false,
      );
      NativeDspPipeline.instance.setProcessorEnabled(
        'dsp.replaygain',
        enabled: false,
      );
      NativeDspPipeline.instance.setProcessorEnabled(
        'dsp.loudness',
        enabled: false,
      );
      NativeDspPipeline.instance.setProcessorEnabled('dsp.peq', enabled: false);
      NativeDspPipeline.instance.setProcessorEnabled(
        'dsp.compressor',
        enabled: false,
      );
      NativeDspPipeline.instance.setProcessorEnabled(
        'dsp.limiter',
        enabled: false,
      );
      NativeDspPipeline.instance.setProcessorEnabled(
        'dsp.soft_clipper',
        enabled: true,
      );
      NativeSoftClipper.instance.setBypass(false);

      // Default threshold (−0.5 dBFS ≈ 0.944 linear).
      NativeSoftClipper.instance.setThresholdDb(-0.5);

      final buf = NativeAudioBuffer.create(
        capacityFrames: 16,
        channelCount: 1,
        sampleRate: 48000,
      );
      expect(buf, isNotNull);
      buf!;

      try {
        // Input: 1.5 (well above 0 dBFS) — would hard-clip without treatment.
        for (var i = 0; i < buf.data.length; i++) {
          buf.data[i] = 1.5;
        }

        NativeDspPipeline.instance.processBuffer(buf);

        for (var i = 0; i < buf.data.length; i++) {
          // Output must be shaped down (below input)
          expect(
            buf.data[i],
            lessThan(1.5),
            reason: 'samples above threshold must be shaped down',
          );
          // Output must not exceed 1.0 (0 dBFS ceiling)
          expect(
            buf.data[i],
            lessThanOrEqualTo(1.0 + 1e-5),
            reason: 'soft clipper must not allow output above 0 dBFS',
          );
          // Output must remain positive (sign-preserving)
          expect(buf.data[i], greaterThan(0.0));
        }
      } finally {
        buf.destroy();
      }
    },
  );

  test('soft clipper: bypass passes overdriven signal unchanged', () async {
    await NativeAudioRuntime.instance.initialize();
    await NativeDspPipeline.instance.initialize();

    // Isolate the soft clipper
    NativeDspPipeline.instance.setProcessorEnabled('dsp.gain', enabled: false);
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.replaygain',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.loudness',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled('dsp.peq', enabled: false);
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.compressor',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.limiter',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.soft_clipper',
      enabled: true,
    );
    NativeSoftClipper.instance.setBypass(true);

    NativeSoftClipper.instance.setThresholdDb(-0.5);

    final buf = NativeAudioBuffer.create(
      capacityFrames: 8,
      channelCount: 1,
      sampleRate: 48000,
    );
    expect(buf, isNotNull);
    buf!;

    try {
      for (var i = 0; i < buf.data.length; i++) {
        buf.data[i] = 1.5; // overdriven
      }

      NativeDspPipeline.instance.processBuffer(buf);

      for (var i = 0; i < buf.data.length; i++) {
        expect(
          buf.data[i],
          closeTo(1.5, 1e-6),
          reason: 'soft clipper bypass must not modify samples',
        );
      }
    } finally {
      buf.destroy();
    }
  });

  // ── NativeCrossfeed tests (Phase 7) ──────────────────────────────────────

  test('crossfeed: default bypass is off', () async {
    await NativeAudioRuntime.instance.initialize();
    await NativeDspPipeline.instance.initialize();
    expect(NativeCrossfeed.instance.bypass, isFalse);
  });

  test('crossfeed: bypass round-trips correctly', () async {
    await NativeAudioRuntime.instance.initialize();
    await NativeDspPipeline.instance.initialize();

    NativeCrossfeed.instance.setBypass(true);
    expect(NativeCrossfeed.instance.bypass, isTrue);

    NativeCrossfeed.instance.setBypass(false);
    expect(NativeCrossfeed.instance.bypass, isFalse);
  });

  test('crossfeed: setParams returns NATIVE_RUNTIME_OK (0)', () async {
    await NativeAudioRuntime.instance.initialize();
    await NativeDspPipeline.instance.initialize();

    final status = NativeCrossfeed.instance.setParams(
      amount: 0.3,
      cutoffHz: 700.0,
      hfCompDb: 3.0,
      hfCompHz: 4000.0,
      width: 1.0,
      sampleRate: 48000.0,
    );
    expect(status, equals(0)); // NATIVE_RUNTIME_OK
  });

  test('crossfeed: bypass passes stereo audio unchanged', () async {
    await NativeAudioRuntime.instance.initialize();
    await NativeDspPipeline.instance.initialize();

    // Isolate the crossfeed processor
    NativeDspPipeline.instance.setProcessorEnabled('dsp.gain', enabled: false);
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.replaygain',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.loudness',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled('dsp.peq', enabled: false);
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.compressor',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.limiter',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.soft_clipper',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.crossfeed',
      enabled: true,
    );
    NativeCrossfeed.instance.setBypass(true);

    final buf = NativeAudioBuffer.create(
      capacityFrames: 16,
      channelCount: 2,
      sampleRate: 48000,
    );
    expect(buf, isNotNull);
    buf!;

    try {
      for (var i = 0; i < buf.data.length; i++) {
        buf.data[i] = (i % 2 == 0) ? 0.6 : 0.2; // L=0.6, R=0.2
      }
      // Copy expected values before processing
      final expected = List<double>.from(buf.data);

      NativeDspPipeline.instance.processBuffer(buf);

      for (var i = 0; i < buf.data.length; i++) {
        expect(
          buf.data[i],
          closeTo(expected[i], 1e-6),
          reason: 'crossfeed bypass must leave all samples untouched',
        );
      }
    } finally {
      buf.destroy();
    }
  });

  test('crossfeed: mono signal passes through unchanged', () async {
    await NativeAudioRuntime.instance.initialize();
    await NativeDspPipeline.instance.initialize();

    // Isolate the crossfeed
    NativeDspPipeline.instance.setProcessorEnabled('dsp.gain', enabled: false);
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.replaygain',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.loudness',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled('dsp.peq', enabled: false);
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.compressor',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.limiter',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.soft_clipper',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.crossfeed',
      enabled: true,
    );
    NativeCrossfeed.instance.setBypass(false);

    // Mono buffer — crossfeed must be a no-op for channels < 2
    final buf = NativeAudioBuffer.create(
      capacityFrames: 16,
      channelCount: 1,
      sampleRate: 48000,
    );
    expect(buf, isNotNull);
    buf!;

    try {
      for (var i = 0; i < buf.data.length; i++) {
        buf.data[i] = 0.7;
      }
      NativeDspPipeline.instance.processBuffer(buf);
      for (var i = 0; i < buf.data.length; i++) {
        expect(
          buf.data[i],
          closeTo(0.7, 1e-6),
          reason: 'mono signal must pass through crossfeed unchanged',
        );
      }
    } finally {
      buf.destroy();
    }
  });

  test(
    'crossfeed: blends channels (L and R outputs differ from hard-panned input)',
    () async {
      await NativeAudioRuntime.instance.initialize();
      await NativeDspPipeline.instance.initialize();

      // Isolate the crossfeed
      NativeDspPipeline.instance.setProcessorEnabled(
        'dsp.gain',
        enabled: false,
      );
      NativeDspPipeline.instance.setProcessorEnabled(
        'dsp.replaygain',
        enabled: false,
      );
      NativeDspPipeline.instance.setProcessorEnabled(
        'dsp.loudness',
        enabled: false,
      );
      NativeDspPipeline.instance.setProcessorEnabled('dsp.peq', enabled: false);
      NativeDspPipeline.instance.setProcessorEnabled(
        'dsp.compressor',
        enabled: false,
      );
      NativeDspPipeline.instance.setProcessorEnabled(
        'dsp.limiter',
        enabled: false,
      );
      NativeDspPipeline.instance.setProcessorEnabled(
        'dsp.soft_clipper',
        enabled: false,
      );
      NativeDspPipeline.instance.setProcessorEnabled(
        'dsp.crossfeed',
        enabled: true,
      );
      NativeCrossfeed.instance.setBypass(false);

      // Maximum crossfeed with a low cutoff to see strong blending.
      // Input: hard-panned — L=0.8, R=0.0.
      // After crossfeed: R_out must receive some of L's energy (> 0).
      // L_out must be reduced (< 0.8) due to normalization.
      NativeCrossfeed.instance.setParams(
        amount: 0.8, // strong crossfeed
        cutoffHz: 2000.0, // high cutoff → more blending
        hfCompDb: 0.0, // no HF compensation (isolate blending effect)
        hfCompHz: 4000.0,
        width: 1.0,
        sampleRate: 48000.0,
      );

      // Use a large buffer so the LP filter fully settles.
      final buf = NativeAudioBuffer.create(
        capacityFrames: 256,
        channelCount: 2,
        sampleRate: 48000,
      );
      expect(buf, isNotNull);
      buf!;

      try {
        // Hard-panned: L = 0.8, R = 0.0
        for (var f = 0; f < 256; f++) {
          buf.data[f * 2 + 0] = 0.8; // L
          buf.data[f * 2 + 1] = 0.0; // R
        }

        NativeDspPipeline.instance.processBuffer(buf);

        // After filter settles (second half of buffer), check blending:
        final midL = buf.data[(128 * 2) + 0]; // L output
        final midR = buf.data[(128 * 2) + 1]; // R output

        // R output must have received energy from L's filtered cross-path
        expect(
          midR,
          greaterThan(0.001),
          reason: 'crossfeed must blend L energy into R channel',
        );
        // L output must be normalized (less than input 0.8)
        expect(
          midL,
          lessThan(0.8),
          reason: 'crossfeed normalization must reduce L output below input',
        );
        // Both channels must be positive
        expect(midL, greaterThan(0.0));
        expect(midR, greaterThan(0.0));
        // R output must be less than L output (L is still dominant)
        expect(
          midR,
          lessThan(midL),
          reason: 'L channel must remain dominant after crossfeed',
        );
      } finally {
        buf.destroy();
      }
    },
  );

  test('crossfeed: amount=0 produces identity (no blending)', () async {
    await NativeAudioRuntime.instance.initialize();
    await NativeDspPipeline.instance.initialize();

    // Isolate the crossfeed
    NativeDspPipeline.instance.setProcessorEnabled('dsp.gain', enabled: false);
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.replaygain',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.loudness',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled('dsp.peq', enabled: false);
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.compressor',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.limiter',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.soft_clipper',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.crossfeed',
      enabled: true,
    );
    NativeCrossfeed.instance.setBypass(false);

    // amount=0: norm = 1/(1+0) = 1; cross = 0×norm = 0; HF comp off
    // → direct_L×1 + 0 = direct_L = HFshelf_identity(L) = L (for hfCompDb=0)
    // → width=1.0 → identity matrix
    // Result: L_out = L_in, R_out = R_in (identity)
    NativeCrossfeed.instance.setParams(
      amount: 0.0,
      cutoffHz: 700.0,
      hfCompDb: 0.0, // no HF comp → identity biquad
      hfCompHz: 4000.0,
      width: 1.0,
      sampleRate: 48000.0,
    );

    final buf = NativeAudioBuffer.create(
      capacityFrames: 32,
      channelCount: 2,
      sampleRate: 48000,
    );
    expect(buf, isNotNull);
    buf!;

    try {
      for (var f = 0; f < 32; f++) {
        buf.data[f * 2 + 0] = 0.6;
        buf.data[f * 2 + 1] = 0.3;
      }

      NativeDspPipeline.instance.processBuffer(buf);

      // After filter settles, steady-state output must match input.
      for (var f = 16; f < 32; f++) {
        expect(
          buf.data[f * 2 + 0],
          closeTo(0.6, 1e-5),
          reason: 'amount=0 must not change L',
        );
        expect(
          buf.data[f * 2 + 1],
          closeTo(0.3, 1e-5),
          reason: 'amount=0 must not change R',
        );
      }
    } finally {
      buf.destroy();
    }
  });

  test('crossfeed: width=0 collapses to mono (L_out == R_out)', () async {
    await NativeAudioRuntime.instance.initialize();
    await NativeDspPipeline.instance.initialize();

    // Isolate the crossfeed
    NativeDspPipeline.instance.setProcessorEnabled('dsp.gain', enabled: false);
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.replaygain',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.loudness',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled('dsp.peq', enabled: false);
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.compressor',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.limiter',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.soft_clipper',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.crossfeed',
      enabled: true,
    );
    NativeCrossfeed.instance.setBypass(false);

    // width=0 → width matrix is mono matrix (L_out = R_out = mid)
    NativeCrossfeed.instance.setParams(
      amount: 0.3,
      cutoffHz: 700.0,
      hfCompDb: 0.0,
      hfCompHz: 4000.0,
      width: 0.0, // full mono
      sampleRate: 48000.0,
    );

    final buf = NativeAudioBuffer.create(
      capacityFrames: 128,
      channelCount: 2,
      sampleRate: 48000,
    );
    expect(buf, isNotNull);
    buf!;

    try {
      // Asymmetric input
      for (var f = 0; f < 128; f++) {
        buf.data[f * 2 + 0] = 0.7;
        buf.data[f * 2 + 1] = 0.3;
      }

      NativeDspPipeline.instance.processBuffer(buf);

      // After filter settles, L_out must equal R_out (mono)
      for (var f = 64; f < 128; f++) {
        expect(
          buf.data[f * 2 + 0],
          closeTo(buf.data[f * 2 + 1], 1e-5),
          reason: 'width=0 must produce identical L and R (mono)',
        );
      }
    } finally {
      buf.destroy();
    }
  });

  // ── NativeSoftClipper (Phase 6) — symmetry test (kept below crossfeed) ───

  test('soft clipper: negative samples are shaped symmetrically', () async {
    await NativeAudioRuntime.instance.initialize();
    await NativeDspPipeline.instance.initialize();

    // Isolate the soft clipper
    NativeDspPipeline.instance.setProcessorEnabled('dsp.gain', enabled: false);
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.replaygain',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.loudness',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled('dsp.peq', enabled: false);
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.compressor',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.limiter',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.soft_clipper',
      enabled: true,
    );
    NativeSoftClipper.instance.setBypass(false);
    NativeSoftClipper.instance.setThresholdDb(-0.5);

    final bufPos = NativeAudioBuffer.create(
      capacityFrames: 8,
      channelCount: 1,
      sampleRate: 48000,
    );
    final bufNeg = NativeAudioBuffer.create(
      capacityFrames: 8,
      channelCount: 1,
      sampleRate: 48000,
    );
    expect(bufPos, isNotNull);
    expect(bufNeg, isNotNull);
    bufPos!;
    bufNeg!;

    try {
      for (var i = 0; i < bufPos.data.length; i++) {
        bufPos.data[i] = 1.2;
      }
      for (var i = 0; i < bufNeg.data.length; i++) {
        bufNeg.data[i] = -1.2;
      }

      NativeDspPipeline.instance.processBuffer(bufPos);
      NativeDspPipeline.instance.processBuffer(bufNeg);

      for (var i = 0; i < bufPos.data.length; i++) {
        expect(
          bufPos.data[i],
          greaterThan(0),
          reason: 'positive input must produce positive output',
        );
        expect(
          bufNeg.data[i],
          lessThan(0),
          reason: 'negative input must produce negative output',
        );
        // Symmetry: |y(+x)| == |y(-x)|
        expect(
          bufPos.data[i],
          closeTo(-bufNeg.data[i], 1e-5),
          reason: 'soft clipper must be sign-symmetric',
        );
      }
    } finally {
      bufPos.destroy();
      bufNeg.destroy();
    }
  });

  // ── NativeLoudnessNorm (Phase 8.5, hardening pass) ───────────────────────
  //
  // Verifies the BS.1770-4 production-hardening rewrite: per-channel power
  // summation (the fixed stereo-averaging bug), LFE exclusion, the absolute
  // gate, and NaN fail-open behavior. All isolate the loudness processor by
  // disabling every other pipeline stage.

  void isolateLoudness() {
    NativeDspPipeline.instance.setProcessorEnabled('dsp.gain', enabled: false);
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.replaygain',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled('dsp.peq', enabled: false);
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.compressor',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.crossfeed',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.limiter',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.soft_clipper',
      enabled: false,
    );
    NativeDspPipeline.instance.setProcessorEnabled(
      'dsp.loudness',
      enabled: true,
    );
  }

  NativeAudioBuffer sineBuffer({
    required int frames,
    required int channels,
    required int sampleRate,
    required double amplitude,
    List<int>? silentChannels,
  }) {
    final buf = NativeAudioBuffer.create(
      capacityFrames: frames,
      channelCount: channels,
      sampleRate: sampleRate,
    );
    expect(buf, isNotNull);
    buf!;
    const freqHz = 1000.0;
    for (var f = 0; f < frames; f++) {
      final sample =
          amplitude * math.sin(2 * math.pi * freqHz * f / sampleRate);
      for (var ch = 0; ch < channels; ch++) {
        final silent = silentChannels?.contains(ch) ?? false;
        buf.data[f * channels + ch] = silent ? 0.0 : sample;
      }
    }
    return buf;
  }

  test('loudness: default bypass is true (starts disabled)', () async {
    await NativeAudioRuntime.instance.initialize();
    await NativeDspPipeline.instance.initialize();
    expect(NativeLoudnessNorm.instance.bypass, isTrue);
  });

  test('loudness: bypass round-trips correctly', () async {
    await NativeAudioRuntime.instance.initialize();
    await NativeDspPipeline.instance.initialize();

    NativeLoudnessNorm.instance.setBypass(false);
    expect(NativeLoudnessNorm.instance.bypass, isFalse);

    NativeLoudnessNorm.instance.setBypass(true);
    expect(NativeLoudnessNorm.instance.bypass, isTrue);
  });

  test('loudness: bypass passes audio unchanged', () async {
    await NativeAudioRuntime.instance.initialize();
    await NativeDspPipeline.instance.initialize();
    isolateLoudness();
    NativeLoudnessNorm.instance.setBypass(true);

    final buf = NativeAudioBuffer.create(
      capacityFrames: 8,
      channelCount: 2,
      sampleRate: 48000,
    );
    expect(buf, isNotNull);
    buf!;
    try {
      for (var i = 0; i < buf.data.length; i++) {
        buf.data[i] = 0.42;
      }
      NativeDspPipeline.instance.processBuffer(buf);
      for (var i = 0; i < buf.data.length; i++) {
        expect(buf.data[i], closeTo(0.42, 1e-6));
      }
    } finally {
      buf.destroy();
    }
  });

  test(
    'loudness: stereo (identical L=R) reads ~3.01 dB louder than mono '
    'at the same per-channel amplitude — regression test for the fixed '
    'channel-averaging bug (BS.1770-4 sums channel power, it does not '
    'average it)',
    () async {
      await NativeAudioRuntime.instance.initialize();
      await NativeDspPipeline.instance.initialize();
      isolateLoudness();
      NativeLoudnessNorm.instance.reset();
      NativeLoudnessNorm.instance.setBypass(false);

      const sampleRate = 48000;
      // 600 ms: past the first 400 ms gating block plus one extra 100 ms hop.
      final frames = (sampleRate * 0.6).round();

      final monoBuf = sineBuffer(
        frames: frames,
        channels: 1,
        sampleRate: sampleRate,
        amplitude: 0.5,
      );
      try {
        NativeDspPipeline.instance.processBuffer(monoBuf);
      } finally {
        monoBuf.destroy();
      }
      final monoLufs = NativeLoudnessNorm.instance.measuredLufs;

      NativeLoudnessNorm.instance.reset();
      final stereoBuf = sineBuffer(
        frames: frames,
        channels: 2,
        sampleRate: sampleRate,
        amplitude: 0.5,
      );
      try {
        NativeDspPipeline.instance.processBuffer(stereoBuf);
      } finally {
        stereoBuf.destroy();
      }
      final stereoLufs = NativeLoudnessNorm.instance.measuredLufs;

      expect(
        monoLufs,
        greaterThan(-99.0),
        reason: 'mono block should have gated in in 600 ms',
      );
      expect(
        stereoLufs,
        greaterThan(-99.0),
        reason: 'stereo block should have gated in in 600 ms',
      );
      expect(
        stereoLufs - monoLufs,
        closeTo(3.0103, 0.05),
        reason:
            'identical L=R channels must sum power (+3.01 dB), not average '
            'it (which would read identically to mono — the historical bug)',
      );
    },
  );

  test(
    'loudness: LFE channel (index 3 of 6) is excluded from the measurement',
    () async {
      await NativeAudioRuntime.instance.initialize();
      await NativeDspPipeline.instance.initialize();
      isolateLoudness();
      NativeLoudnessNorm.instance.reset();
      NativeLoudnessNorm.instance.setBypass(false);

      const sampleRate = 48000;
      final frames = (sampleRate * 0.6).round();

      // Full-scale tone ONLY on channel 3 (LFE in the assumed 5.1 layout);
      // all other channels silent. BS.1770-4 gives LFE a 0.0 power weight,
      // so this must never pass the absolute gate.
      final buf = sineBuffer(
        frames: frames,
        channels: 6,
        sampleRate: sampleRate,
        amplitude: 0.9,
        silentChannels: [0, 1, 2, 4, 5],
      );
      try {
        NativeDspPipeline.instance.processBuffer(buf);
      } finally {
        buf.destroy();
      }

      expect(
        NativeLoudnessNorm.instance.measuredLufs,
        equals(-99.0),
        reason: 'LFE-only content must never gate in (G_LFE == 0.0)',
      );
    },
  );

  test(
    'loudness: content below the absolute gate never updates measuredLufs',
    () async {
      await NativeAudioRuntime.instance.initialize();
      await NativeDspPipeline.instance.initialize();
      isolateLoudness();
      NativeLoudnessNorm.instance.reset();
      NativeLoudnessNorm.instance.setBypass(false);

      const sampleRate = 48000;
      final frames = (sampleRate * 0.6).round();

      // −70 LUFS absolute gate ≈ very small linear amplitude. 1e-5 peak is
      // roughly −140 dBFS-ish after K-weighting attenuation — deep silence.
      final buf = sineBuffer(
        frames: frames,
        channels: 2,
        sampleRate: sampleRate,
        amplitude: 0.00001,
      );
      try {
        NativeDspPipeline.instance.processBuffer(buf);
      } finally {
        buf.destroy();
      }

      expect(
        NativeLoudnessNorm.instance.measuredLufs,
        equals(-99.0),
        reason: 'near-silent content must stay gated out (sentinel unchanged)',
      );
    },
  );

  test(
    'loudness: a single NaN sample does not poison filter state or produce '
    'non-finite output (fail-open defensive guard)',
    () async {
      await NativeAudioRuntime.instance.initialize();
      await NativeDspPipeline.instance.initialize();
      isolateLoudness();
      NativeLoudnessNorm.instance.reset();
      NativeLoudnessNorm.instance.setBypass(false);

      const sampleRate = 48000;
      final frames = (sampleRate * 0.6).round();

      final buf = sineBuffer(
        frames: frames,
        channels: 2,
        sampleRate: sampleRate,
        amplitude: 0.5,
      );
      try {
        // Inject a NaN into the very first frame, both channels.
        buf.data[0] = double.nan;
        buf.data[1] = double.nan;

        NativeDspPipeline.instance.processBuffer(buf);

        for (var i = 0; i < buf.data.length; i++) {
          expect(
            buf.data[i].isFinite,
            isTrue,
            reason:
                'a single NaN input sample must never propagate to a '
                'non-finite output sample',
          );
        }
        expect(
          NativeLoudnessNorm.instance.measuredLufs.isFinite,
          isTrue,
          reason: 'measured LUFS must remain finite despite the NaN input',
        );
      } finally {
        buf.destroy();
      }
    },
  );

  test('loudness: reset clears gating state back to the sentinel', () async {
    await NativeAudioRuntime.instance.initialize();
    await NativeDspPipeline.instance.initialize();
    isolateLoudness();
    NativeLoudnessNorm.instance.reset();
    NativeLoudnessNorm.instance.setBypass(false);

    const sampleRate = 48000;
    final frames = (sampleRate * 0.6).round();
    final buf = sineBuffer(
      frames: frames,
      channels: 2,
      sampleRate: sampleRate,
      amplitude: 0.5,
    );
    try {
      NativeDspPipeline.instance.processBuffer(buf);
    } finally {
      buf.destroy();
    }
    expect(NativeLoudnessNorm.instance.measuredLufs, greaterThan(-99.0));

    NativeLoudnessNorm.instance.reset();
    expect(NativeLoudnessNorm.instance.measuredLufs, equals(-99.0));
    expect(NativeLoudnessNorm.instance.appliedGainDb, equals(0.0));
  });
}
