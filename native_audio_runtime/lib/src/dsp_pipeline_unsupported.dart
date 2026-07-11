/// Fallback DSP pipeline and AudioBuffer wrappers for platforms without
/// `dart:ffi` (currently: web). Selected automatically by the conditional
/// export in `native_audio_runtime.dart` — never import this file directly.
///
/// All methods are safe no-ops / stubs. [NativeAudioBuffer.create] always
/// returns `null` because there is no native heap to allocate from.
/// [NativeDspPipeline.isInitialized] is always `false`.
library;

import 'dart:typed_data';

import 'runtime_types.dart';

// ── NativeAudioBuffer stub ────────────────────────────────────────────────────

/// Unsupported-platform stub for [NativeAudioBuffer].
/// [create] always returns `null` — no native allocation is possible.
class NativeAudioBuffer {
  NativeAudioBuffer._();

  /// Always returns `null` on unsupported platforms.
  // ignore: avoid_unused_constructor_parameters
  static NativeAudioBuffer? create({
    required int capacityFrames,
    required int channelCount,
    required int sampleRate,
  }) =>
      null;

  void destroy() {}

  Float32List get data => Float32List(0);

  int get capacityFrames => 0;
  int get frameCount => 0;

  int setFrameCount(int n) => 0;

  int get channelCount => 0;
  int get sampleRate => 0;
  int get timestampUs => 0;

  void setTimestampUs(int us) {}
}

// ── NativeDspPipeline stub ────────────────────────────────────────────────────

/// Unsupported-platform stub for [NativeDspPipeline].
/// [isInitialized] is always `false`; all control methods are no-ops.
class NativeDspPipeline {
  NativeDspPipeline._();

  static final NativeDspPipeline instance = NativeDspPipeline._();

  bool get isInitialized => false;

  /// Always false on unsupported platforms (no native library).
  bool get isInitializedNative => false;

  Future<void> initialize() async {}

  Future<void> dispose() async {}

  int processBuffer(NativeAudioBuffer buffer) => NativeRuntimeStatus.unsupportedPlatform.index;

  void reset() {}

  int get processorCount => 0;

  int get totalLatencyFrames => 0;

  String? processorIdAt(int index) => null;

  void setProcessorEnabled(String id, {required bool enabled}) {}

  bool isProcessorEnabled(String id) => false;

  void setGainDb(double gainDb) {}

  double get gainDb => 0.0;

  void setGainBypass(bool bypass) {}

  bool get gainBypass => false;
}

// ── NativeParametricEq stub ───────────────────────────────────────────────────

/// Unsupported-platform stub for [NativeParametricEq].
/// All methods are safe no-ops. [bypass] is always `false`.
class NativeParametricEq {
  NativeParametricEq._();

  static final NativeParametricEq instance = NativeParametricEq._();

  int setBand({
    required int bandIndex,
    required bool enabled,
    required PeqFilterType type,
    required double freqHz,
    required double q,
    required double gainDb,
    required double sampleRate,
  }) =>
      NativeRuntimeStatus.unsupportedPlatform.index;

  int setBandEnabled(int bandIndex, {required bool enabled}) =>
      NativeRuntimeStatus.unsupportedPlatform.index;

  bool isBandEnabled(int bandIndex) => false;

  void setBypass(bool bypass) {}

  bool get bypass => false;

  int get maxBands => 0;

  int get bandCount => 0;
}
