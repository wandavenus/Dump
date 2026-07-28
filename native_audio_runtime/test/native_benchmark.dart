// Performance benchmark for the native DSP pipeline.
//
// Mirrors the per-frame work a real audio thread does:
//   1. Allocate an interleaved stereo buffer of N frames.
//   2. Fill it with a deterministic sine wave (so the DSP has real work to do).
//   3. Push it through NativeDspPipeline.processBuffer repeatedly.
//   4. Measure throughput in frames/sec and report as `test` group results
//      so the numbers surface in CI logs without failing the build.
//
// The benchmark is tolerant: it always passes (use `expect` only for sanity
// ranges) and is meant for trend tracking, not gating.
//
// The native_audio_runtime_test.dart file at the root of this directory
// contains the real functional coverage — this file only measures speed.

import 'dart:math' as math;

import 'package:native_audio_runtime/native_audio_runtime.dart';
import 'package:test/test.dart';

const int _kChannels = 2;
const int _kFrames = 1024; // ~23 ms @ 44.1 kHz — a typical callback size
const int _kSampleRate = 44100;
const int _kWarmupIters = 64;
const int _kMeasureIters = 2048;

void _fillSine(NativeAudioBuffer buf, double freqHz) {
  final data = buf.data;
  final twoPiF = 2 * math.pi * freqHz;
  for (int i = 0; i < buf.frameCount; i++) {
    final sample = math.sin(twoPiF * i / _kSampleRate);
    for (int c = 0; c < _kChannels; c++) {
      data[i * _kChannels + c] = sample;
    }
  }
}

void main() {
  group('native_audio_runtime benchmark', () {
    late NativeAudioBuffer benchBuf;

    setUpAll(() async {
      await NativeAudioRuntime.instance.initialize();
      final pipeline = NativeDspPipeline.instance;
      if (!pipeline.isInitialized) {
        await pipeline.initialize();
      }
      // dsp.gain is auto-registered by initialize(); set unity so the
      // processor doesn't attenuate the sine wave we're feeding it.
      pipeline.setGainDb(0.0);

      benchBuf = NativeAudioBuffer.create(
        capacityFrames: _kFrames,
        channelCount: _kChannels,
        sampleRate: _kSampleRate,
      )!;
    });

    tearDownAll(() async {
      benchBuf.destroy();
      await NativeDspPipeline.instance.dispose();
      await NativeAudioRuntime.instance.dispose();
    });

    test('pipeline init is sub-second', () async {
      // Re-initialize to time a fresh init. dispose() first to avoid
      // "already initialized" errors.
      final pipeline = NativeDspPipeline.instance;
      await pipeline.dispose();
      final sw = Stopwatch()..start();
      await pipeline.initialize();
      sw.stop();
      // 2 s is generous; on a CI runner with cold caches this still leaves
      // plenty of headroom while catching a real regression.
      expect(
        sw.elapsedMilliseconds,
        lessThan(2000),
        reason: 'pipeline init took ${sw.elapsedMilliseconds} ms',
      );
      // ignore: avoid_print
      print('[bench] init=${sw.elapsedMilliseconds}ms');
      // Restore the processor state the rest of the suite expects.
      pipeline.setGainDb(0.0);
    });

    test(
      'processBuffer throughput ($_kMeasureIters x $_kFrames frames)',
      () async {
        final pipeline = NativeDspPipeline.instance;
        _fillSine(benchBuf, 440.0);

        // Warm up — let any lazy JIT / first-call caches settle.
        for (int i = 0; i < _kWarmupIters; i++) {
          pipeline.processBuffer(benchBuf);
        }

        final sw = Stopwatch()..start();
        for (int i = 0; i < _kMeasureIters; i++) {
          pipeline.processBuffer(benchBuf);
        }
        sw.stop();

        final frames = _kMeasureIters * _kFrames;
        final secs = sw.elapsedMicroseconds / 1e6;
        final fps = frames / secs;
        // ignore: avoid_print
        print(
          '[bench] processed $frames frames in ${sw.elapsedMilliseconds}ms '
          '(${(fps / 1000).toStringAsFixed(1)}k frames/sec)',
        );

        // Soft floor: 10k frames/sec. The native pipeline is way above this
        // in practice (millions of frames/sec) — this only catches catastrophic
        // regressions, e.g. accidental FFI-per-call overhead.
        expect(
          fps,
          greaterThan(10000),
          reason: 'throughput $fps fps is below the sanity floor',
        );
      },
    );
  });
}
