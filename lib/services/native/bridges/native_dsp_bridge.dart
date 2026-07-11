import '../contracts/native_module.dart';
import '../models/native_module_status.dart';

/// Stub bridge for a future native C++ DSP module.
///
/// ## Intended future responsibilities
///
/// When implemented, this bridge will own the Dart ↔ C++ boundary for:
///   - Parametric / graphic equalizer (native precision)
///   - Bass boost
///   - Virtualizer / spatial audio
///   - Dynamic range compressor
///   - Resampler (e.g. SoX / libsamplerate)
///
/// ## Current state (Phase 2.5)
///
/// This is a **pure stub** — no native code exists yet.
/// All methods are no-ops that return safe defaults.
/// The class compiles cleanly and integrates into [PlaybackManager] so that
/// future C++ DSP work only requires filling in the method bodies and adding
/// the corresponding Kotlin JNI / Dart FFI glue.
///
/// ## Integration plan (future)
///
/// 1. Add `android/app/src/main/cpp/dsp/` with CMakeLists.txt.
/// 2. Expose a MethodChannel `musicplayer/native_dsp` in MainActivity.kt.
/// 3. Replace stub method bodies with channel calls / FFI calls.
/// 4. Register capability keys in [queryCapabilities].
///
/// ## Extension points
///
/// ```
/// // DSP preset (future)
/// Future<void> applyPreset(DspPreset preset) → channel call
///
/// // Per-band gain (future)
/// Future<void> setBandGain(int band, double gainDb) → channel call
///
/// // Spatial audio (future)
/// Future<void> setSpatialAudioMode(SpatialMode mode) → channel call
/// ```
class NativeDspBridge implements NativeModule {
  NativeDspBridge._();

  static final NativeDspBridge instance = NativeDspBridge._();

  NativeModuleStatus _status = NativeModuleStatus.uninitialized;

  // ── NativeModule contract ─────────────────────────────────────────────────

  @override
  String get moduleId => 'native_dsp';

  @override
  String get displayName => 'Native DSP';

  @override
  bool get isAvailable => _status == NativeModuleStatus.available;

  @override
  Future<void> initialize() async {
    if (_status != NativeModuleStatus.uninitialized) return;

    // TODO(phase-dsp): Open MethodChannel 'musicplayer/native_dsp'.
    // TODO(phase-dsp): Query native side for DSP hardware availability.
    // TODO(phase-dsp): Initialize C++ DSP engine via JNI / FFI.

    // Stub: module is not yet available — no native code exists.
    _status = NativeModuleStatus.unavailable;
  }

  @override
  Future<void> dispose() async {
    if (_status == NativeModuleStatus.disposed) return;

    // TODO(phase-dsp): Tear down C++ DSP engine resources.

    _status = NativeModuleStatus.disposed;
  }

  @override
  Future<List<NativeCapability>> queryCapabilities() async {
    // Stub — returns all capabilities as unsupported until native code ships.
    return const [
      NativeCapability(key: 'dsp.equalizer',    supported: false),
      NativeCapability(key: 'dsp.bass_boost',   supported: false),
      NativeCapability(key: 'dsp.virtualizer',  supported: false),
      NativeCapability(key: 'dsp.compressor',   supported: false),
      NativeCapability(key: 'dsp.resampler',    supported: false),
      NativeCapability(key: 'dsp.spatial_audio',supported: false),
    ];
  }

  // ── Extension points (future DSP API surface) ─────────────────────────────

  /// Future: apply a named DSP preset.
  /// Currently a no-op — method signature is locked for forward compatibility.
  Future<void> applyPreset(String presetName) async {
    // TODO(phase-dsp): channel.invokeMethod('applyPreset', {'name': presetName});
  }

  /// Future: set a single equalizer band gain.
  Future<void> setBandGain(int bandIndex, double gainDb) async {
    // TODO(phase-dsp): channel.invokeMethod('setBandGain', {'band': bandIndex, 'gain': gainDb});
  }

  /// Future: enable or disable the C++ DSP pipeline.
  Future<void> setEnabled({required bool enabled}) async {
    // TODO(phase-dsp): channel.invokeMethod('setEnabled', {'enabled': enabled});
  }

  /// Future: register a custom audio processor (hook for FFT, visualizer, etc.).
  Future<void> registerProcessor(String processorId) async {
    // TODO(phase-dsp): channel.invokeMethod('registerProcessor', {'id': processorId});
  }
}
