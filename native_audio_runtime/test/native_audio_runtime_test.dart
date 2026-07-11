// Runs the REAL native runtime, compiled for the host platform by the
// native-assets build hook (`hook/build.dart`) when this test executes.
//
// Phase 4 additions: DSP pipeline init, gain processor registration,
// buffer processing (unity gain / non-zero gain / bypass), enable/disable.
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

  test('capabilities include dsp.gain and dsp.pipeline as supported (Phase 4)',
      () async {
    await NativeAudioRuntime.instance.initialize();
    final caps = NativeAudioRuntime.instance.capabilities;
    expect(caps, isNotEmpty);
    expect(caps.map((c) => c.key), containsAll(['dsp.gain', 'dsp.pipeline']));
    final gain = caps.firstWhere((c) => c.key == 'dsp.gain');
    final pipeline = caps.firstWhere((c) => c.key == 'dsp.pipeline');
    expect(gain.supported, isTrue);
    expect(pipeline.supported, isTrue);
    // All other capabilities remain unsupported placeholders.
    final others = caps.where(
        (c) => c.key != 'dsp.gain' && c.key != 'dsp.pipeline');
    expect(others.every((c) => c.supported == false), isTrue);
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
    final status =
        NativeAudioRuntime.instance.registerModule('too_early_module');
    expect(status, NativeRuntimeStatus.notInitialized);
  });

  test('concurrent initialize calls are safe (thread-safety contract)',
      () async {
    final futures = <Future<void>>[
      for (var i = 0; i < 8; i++) NativeAudioRuntime.instance.initialize(),
    ];
    await Future.wait(futures);
    expect(NativeAudioRuntime.instance.isAvailable, isTrue);
  });

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
    await NativeDspPipeline.instance.initialize(); // second call — must not throw
    expect(NativeDspPipeline.instance.isInitialized, isTrue);
  });

  test('gain processor registers and shows up in processorCount', () async {
    await NativeAudioRuntime.instance.initialize();
    await NativeDspPipeline.instance.initialize();
    expect(NativeDspPipeline.instance.processorCount, equals(1));
    expect(NativeDspPipeline.instance.processorIdAt(0), equals('dsp.gain'));
  });

  test('gain processor defaults to 0 dBFS and bypass off', () async {
    await NativeAudioRuntime.instance.initialize();
    await NativeDspPipeline.instance.initialize();
    expect(NativeDspPipeline.instance.gainDb,
        closeTo(0.0, 0.001));
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

    // Unity gain (0 dBFS).
    NativeDspPipeline.instance.setGainDb(0.0);
    NativeDspPipeline.instance.setGainBypass(false);

    final buf = NativeAudioBuffer.create(
        capacityFrames: 4, channelCount: 2, sampleRate: 44100);
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
        expect(buf.data[i], closeTo(0.5, 1e-5),
            reason: 'unity gain must not change samples');
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

    final buf = NativeAudioBuffer.create(
        capacityFrames: 8, channelCount: 1, sampleRate: 48000);
    expect(buf, isNotNull);
    buf!;

    try {
      final data = buf.data;
      for (var i = 0; i < data.length; i++) {
        data[i] = 1.0;
      }

      NativeDspPipeline.instance.processBuffer(buf);

      for (var i = 0; i < buf.data.length; i++) {
        expect(buf.data[i], closeTo(expectedLinear, 1e-4),
            reason: '+6 dBFS on 1.0 must yield ~1.9953');
      }
    } finally {
      buf.destroy();
    }
  });

  test('gain processor bypass is true zero-copy', () async {
    await NativeAudioRuntime.instance.initialize();
    await NativeDspPipeline.instance.initialize();

    NativeDspPipeline.instance.setGainDb(20.0); // high gain — would change samples
    NativeDspPipeline.instance.setGainBypass(true); // but bypass on

    final buf = NativeAudioBuffer.create(
        capacityFrames: 4, channelCount: 2, sampleRate: 44100);
    expect(buf, isNotNull);
    buf!;

    try {
      final data = buf.data;
      for (var i = 0; i < data.length; i++) {
        data[i] = 0.7;
      }

      NativeDspPipeline.instance.processBuffer(buf);

      for (var i = 0; i < buf.data.length; i++) {
        expect(buf.data[i], closeTo(0.7, 1e-6),
            reason: 'bypass must leave samples untouched');
      }
    } finally {
      buf.destroy();
    }
  });

  test('pipeline enable/disable skips processor entirely', () async {
    await NativeAudioRuntime.instance.initialize();
    await NativeDspPipeline.instance.initialize();

    NativeDspPipeline.instance.setGainDb(20.0); // would change samples if applied
    NativeDspPipeline.instance.setGainBypass(false);
    NativeDspPipeline.instance.setProcessorEnabled('dsp.gain', enabled: false);
    expect(NativeDspPipeline.instance.isProcessorEnabled('dsp.gain'), isFalse);

    final buf = NativeAudioBuffer.create(
        capacityFrames: 4, channelCount: 1, sampleRate: 44100);
    expect(buf, isNotNull);
    buf!;

    try {
      final data = buf.data;
      for (var i = 0; i < data.length; i++) {
        data[i] = 0.3;
      }

      NativeDspPipeline.instance.processBuffer(buf);

      for (var i = 0; i < buf.data.length; i++) {
        expect(buf.data[i], closeTo(0.3, 1e-6),
            reason: 'disabled processor must not touch samples');
      }

      // Re-enable and verify gain is applied.
      NativeDspPipeline.instance.setProcessorEnabled('dsp.gain', enabled: true);
      expect(NativeDspPipeline.instance.isProcessorEnabled('dsp.gain'), isTrue);
      NativeDspPipeline.instance.processBuffer(buf);

      final expectedLinear = math.pow(10.0, 20.0 / 20.0); // 10×
      for (var i = 0; i < buf.data.length; i++) {
        expect(buf.data[i], closeTo(0.3 * expectedLinear, 1e-4),
            reason: 're-enabled processor must apply gain');
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

  test('pipeline total latency is 0 (gain processor is sample-synchronous)',
      () async {
    await NativeAudioRuntime.instance.initialize();
    await NativeDspPipeline.instance.initialize();
    expect(NativeDspPipeline.instance.totalLatencyFrames, equals(0));
  });

  test('NativeAudioBuffer metadata is correct', () async {
    await NativeAudioRuntime.instance.initialize();

    final buf = NativeAudioBuffer.create(
        capacityFrames: 16, channelCount: 2, sampleRate: 48000);
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
        capacityFrames: 4, channelCount: 1, sampleRate: 44100);
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
          capacityFrames: -1, channelCount: 2, sampleRate: 44100),
      isNull,
    );
    expect(
      NativeAudioBuffer.create(
          capacityFrames: 16, channelCount: 0, sampleRate: 44100),
      isNull,
    );
  });

  test('pipeline dispose is safe to call without prior initialize', () async {
    // NativeDspPipeline.instance starts un-initialized — dispose must be no-op.
    await NativeDspPipeline.instance.dispose();
    expect(NativeDspPipeline.instance.isInitialized, isFalse);
  });
}
