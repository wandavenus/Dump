/// Shared, platform-agnostic types for [NativeAudioRuntime].
///
/// Kept in their own file (no `dart:ffi` import) so they can be used
/// identically by both the real FFI implementation and the web/unsupported
/// stub without pulling `dart:ffi` into web compilation.
library;

/// Mirrors `NativeRuntimeStatus` in `src/native_audio_runtime.h`.
enum NativeRuntimeStatus {
  ok,
  alreadyInitialized,
  notInitialized,
  unsupportedPlatform,
  duplicateModule,
  moduleLimitReached,
  invalidArgument,
  allocationFailed;

  /// Decode the raw `int32_t` status code returned by native calls.
  static NativeRuntimeStatus fromCode(int code) {
    if (code >= 0 && code < NativeRuntimeStatus.values.length) {
      return NativeRuntimeStatus.values[code];
    }
    return NativeRuntimeStatus.unsupportedPlatform;
  }
}

/// A single capability entry reported by the native runtime.
///
/// Phase 3 ships only placeholder entries (`supported: false`) — no DSP or
/// FFmpeg module exists yet. Real modules will flip these as they land.
class NativeRuntimeCapability {
  /// Dot-separated capability key, e.g. `'dsp.equalizer'`.
  final String key;

  /// Whether this capability is currently supported.
  final bool supported;

  const NativeRuntimeCapability({required this.key, required this.supported});

  @override
  String toString() => 'NativeRuntimeCapability($key, supported=$supported)';
}

/// Outcome of [NativeAAudioProbe.run] — mirrors `NarAAudioProbeResult` in
/// `src/aaudio_probe.h`. Distinct from [NativeRuntimeStatus] since this is a
/// standalone diagnostic, not a DSP pipeline module.
enum AAudioProbeResult {
  ok,
  unsupportedPlatform,
  libraryNotFound,
  symbolMissing,
  builderFailed,
  openFailed;

  /// Decode the raw int32_t code returned by `native_runtime_aaudio_probe()`.
  static AAudioProbeResult fromCode(int code) {
    switch (code) {
      case 0:
        return AAudioProbeResult.ok;
      case -100:
        return AAudioProbeResult.unsupportedPlatform;
      case -101:
        return AAudioProbeResult.libraryNotFound;
      case -102:
        return AAudioProbeResult.symbolMissing;
      case -103:
        return AAudioProbeResult.builderFailed;
      case -104:
        return AAudioProbeResult.openFailed;
      default:
        return AAudioProbeResult.unsupportedPlatform;
    }
  }
}

/// Sharing mode AAudio actually granted — mirrors `aaudio_sharing_mode_t`.
/// `unknown` means the probe never reached a successful stream open.
enum AAudioSharingMode { exclusive, shared, unknown }

/// Performance mode AAudio actually granted — mirrors
/// `aaudio_performance_mode_t`. `unknown` means the probe never reached a
/// successful stream open.
enum AAudioPerformanceMode { none, powerSaving, lowLatency, unknown }

/// Full result of one [NativeAAudioProbe.run] call.
class AAudioProbeReport {
  final AAudioProbeResult result;
  final AAudioSharingMode sharingMode;
  final AAudioPerformanceMode performanceMode;

  /// Human-readable detail (error message, or empty string on success).
  final String detail;

  const AAudioProbeReport({
    required this.result,
    required this.sharingMode,
    required this.performanceMode,
    required this.detail,
  });

  /// True only if AAudio actually granted exclusive-mode MMAP with
  /// low-latency performance — the strongest signal this device supports
  /// AAudio's fast path end to end.
  bool get isExclusiveLowLatency =>
      result == AAudioProbeResult.ok &&
      sharingMode == AAudioSharingMode.exclusive &&
      performanceMode == AAudioPerformanceMode.lowLatency;
}

/// Thrown when a native runtime call fails in a way the caller should
/// handle explicitly (as opposed to a silent "unavailable" state).
class NativeRuntimeException implements Exception {
  final String operation;
  final NativeRuntimeStatus status;

  const NativeRuntimeException(this.operation, this.status);

  @override
  String toString() => 'NativeRuntimeException: $operation failed with $status';
}
