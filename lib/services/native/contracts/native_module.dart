/// Contract for every pluggable native module.
///
/// A native module is any Dart ↔ Native bridge that lives outside the core
/// Media3 playback pipeline — e.g. a C++ DSP processor, an FFmpeg decoder,
/// an FFT analyser, or a loudness scanner.
///
/// ## Lifecycle
///
/// ```
/// NativeModuleRegistry.register(module)
///         ↓
/// PlaybackManager.initialize()
///   └─ NativeModuleRegistry.initializeAll()
///           ↓  [module.initialize()]
///         module runs
///           ↓  [module.dispose()]
/// PlaybackManager.dispose()
///   └─ NativeModuleRegistry.disposeAll()
/// ```
///
/// ## Availability
///
/// [isAvailable] may be `false` on devices that lack the underlying hardware
/// or Android API level.  Callers must check before using capabilities.
///
/// ## Capabilities
///
/// [queryCapabilities] returns a list of [NativeCapability] entries describing
/// what the module can do.  Results should be cached by the module itself;
/// the host calls this once after [initialize].
abstract interface class NativeModule {
  /// Stable identifier — used as the key in capability maps and log messages.
  /// Must be unique across all registered modules.
  /// Convention: lowercase_snake_case  (e.g. 'native_dsp', 'ffmpeg_decoder').
  String get moduleId;

  /// Human-readable name for logs and debug UIs.
  String get displayName;

  /// Allocate resources, open channels, detect hardware.
  /// Must be idempotent — calling twice must not crash.
  Future<void> initialize();

  /// Release all resources held by this module.
  /// Must be safe to call even if [initialize] was never called.
  Future<void> dispose();

  /// Whether this module is functional on the current device/API level.
  /// Evaluated after [initialize] completes.
  bool get isAvailable;

  /// Returns the capabilities this module exposes.
  /// Should be cheap — cache internally on first call.
  Future<List<NativeCapability>> queryCapabilities();
}

// ─── Capability model ─────────────────────────────────────────────────────────

/// A single capability entry reported by a [NativeModule].
class NativeCapability {
  /// Dot-separated capability key (e.g. 'dsp.equalizer', 'decoder.flac').
  final String key;

  /// Whether the capability is supported on this device.
  final bool supported;

  /// Optional version or detail string (e.g. library version, API level).
  final String? version;

  const NativeCapability({
    required this.key,
    required this.supported,
    this.version,
  });

  @override
  String toString() =>
      'NativeCapability($key, supported=$supported${version != null ? ', v$version' : ''})';
}
