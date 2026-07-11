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

/// Thrown when a native runtime call fails in a way the caller should
/// handle explicitly (as opposed to a silent "unavailable" state).
class NativeRuntimeException implements Exception {
  final String operation;
  final NativeRuntimeStatus status;

  const NativeRuntimeException(this.operation, this.status);

  @override
  String toString() =>
      'NativeRuntimeException: $operation failed with $status';
}
