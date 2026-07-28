import 'package:native_audio_runtime/native_audio_runtime.dart';

import '../contracts/native_module.dart';
import '../models/native_module_status.dart';
import '../../boot_trace.dart';

/// FFI bridge for a future native C++ DSP module.
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
/// ## Current state (Phase 3)
///
/// The shared native runtime (`package:native_audio_runtime`) is real and
/// functional — it loads, initializes, reports a version, and accepts this
/// module's registration. No DSP algorithm exists yet: [queryCapabilities]
/// still reports every entry as unsupported. [isAvailable] now reflects
/// whether the native runtime actually loaded and initialized on this
/// device/platform, NOT whether DSP processing works — those are
/// deliberately different questions. See `NATIVE_RUNTIME.md` for the full
/// architecture and the assumptions that could not be validated in this
/// environment (no Android NDK available to cross-compile against).
///
/// ## Integration plan (future)
///
/// 1. Add real DSP entry points to `native_audio_runtime/src/` (new .c/.h
///    files alongside `native_audio_runtime.c`, or a sibling native target).
/// 2. Extend `NativeAudioRuntime` (or add a dedicated FFI binding set) with
///    DSP-specific calls; keep this class's public method signatures.
/// 3. Update [queryCapabilities] to report real support per device.
///
/// ## Extension points
///
/// ```
/// // DSP preset (future)
/// Future<void> applyPreset(DspPreset preset) → FFI call
///
/// // Per-band gain (future)
/// Future<void> setBandGain(int band, double gainDb) → FFI call
///
/// // Spatial audio (future)
/// Future<void> setSpatialAudioMode(SpatialMode mode) → FFI call
/// ```
class NativeDspBridge implements NativeModule {
  NativeDspBridge._();

  static final NativeDspBridge instance = NativeDspBridge._();

  static const String _moduleId = 'native_dsp';

  NativeModuleStatus _status = NativeModuleStatus.uninitialized;

  // ── NativeModule contract ─────────────────────────────────────────────────

  @override
  String get moduleId => _moduleId;

  @override
  String get displayName => 'Native DSP';

  @override
  bool get isAvailable => _status == NativeModuleStatus.available;

  /// Native runtime version string (e.g. `'0.1.0-phase3'`), or `null` if the
  /// runtime never became available on this platform.
  String? get runtimeVersion =>
      isAvailable ? NativeAudioRuntime.instance.version : null;

  @override
  Future<void> initialize() async {
    BootTrace.log('ENTER NativeDspBridge.initialize()');
    if (_status != NativeModuleStatus.uninitialized) {
      BootTrace.log(
        'EXIT  NativeDspBridge.initialize() — already $_status, no-op',
      );
      return;
    }

    try {
      // Shared singleton — idempotent even if FfmpegDecoderBridge already
      // initialized it first (registration order comes from PlaybackManager).
      BootTrace.log('BEFORE await NativeAudioRuntime.instance.initialize()');
      await NativeAudioRuntime.instance.initialize();
      BootTrace.log('AFTER  await NativeAudioRuntime.instance.initialize()');

      if (!NativeAudioRuntime.instance.isAvailable) {
        // Web, or the native library failed to load — no exception, just
        // "unavailable", matching this module's own stub-era contract.
        _status = NativeModuleStatus.unavailable;
        BootTrace.log(
          'EXIT  NativeDspBridge.initialize() — runtime unavailable',
        );
        return;
      }

      final regStatus = NativeAudioRuntime.instance.registerModule(_moduleId);
      _status = switch (regStatus) {
        NativeRuntimeStatus.ok ||
        NativeRuntimeStatus.duplicateModule => NativeModuleStatus.available,
        _ => NativeModuleStatus.unavailable,
      };
      BootTrace.log('EXIT  NativeDspBridge.initialize() — status=$_status');
    } on Object catch (e, st) {
      // Catches all throwables including FFI errors and platform exceptions.
      BootTrace.log('EXCEPTION in NativeDspBridge.initialize(): $e\n$st');
      _status = NativeModuleStatus.error;
    }
  }

  @override
  Future<void> dispose() async {
    if (_status == NativeModuleStatus.disposed) return;

    // Do NOT dispose the shared NativeAudioRuntime here — FfmpegDecoderBridge
    // (or a future module) may still be using it. NativeModuleRegistry
    // disposes modules in reverse order; the runtime itself is disposed once
    // by whichever module happens to run last, which is fine since dispose
    // is idempotent and safe to call multiple times.
    _status = NativeModuleStatus.disposed;
  }

  @override
  Future<List<NativeCapability>> queryCapabilities() async {
    if (!isAvailable) {
      // Runtime unavailable — report the same placeholder set as before,
      // all unsupported, so callers see a stable shape regardless of state.
      return const [
        NativeCapability(key: 'dsp.equalizer', supported: false),
        NativeCapability(key: 'dsp.bass_boost', supported: false),
        NativeCapability(key: 'dsp.virtualizer', supported: false),
        NativeCapability(key: 'dsp.compressor', supported: false),
        NativeCapability(key: 'dsp.resampler', supported: false),
        NativeCapability(key: 'dsp.spatial_audio', supported: false),
      ];
    }

    // Real query against the native runtime — still all `false` (Phase 3
    // ships no DSP), but now sourced from native code instead of hardcoded
    // Dart, proving the round-trip works end-to-end.
    return NativeAudioRuntime.instance.capabilities
        .map((c) => NativeCapability(key: c.key, supported: c.supported))
        .toList();
  }
}
