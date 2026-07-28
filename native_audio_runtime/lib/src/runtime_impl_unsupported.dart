/// Fallback implementation used on platforms without `dart:ffi` (currently:
/// web). Selected automatically by the conditional export in
/// `native_audio_runtime.dart` — never import this file directly.
library;

import 'runtime_types.dart';

class NativeAudioRuntime {
  NativeAudioRuntime._();

  static final NativeAudioRuntime instance = NativeAudioRuntime._();

  bool _initialized = false;

  /// Always false on this platform — there is no native library to load.
  bool get isAvailable => false;

  Future<void> initialize() async {
    // No-op: nothing to initialize when the native library cannot be
    // loaded on this platform. Mirrors the native contract's idempotency
    // (calling twice is safe) without throwing on unsupported platforms.
    _initialized = true;
  }

  Future<void> dispose() async {
    _initialized = false;
  }

  bool get isInitialized => _initialized;

  String get version => 'unsupported-platform';

  List<NativeRuntimeCapability> get capabilities => const [];

  NativeRuntimeStatus registerModule(String moduleId) {
    return NativeRuntimeStatus.unsupportedPlatform;
  }

  List<String> get registeredModuleIds => const [];
}

// ── NativeAAudioProbe stub ────────────────────────────────────────────────────

/// Unsupported-platform stub for [NativeAAudioProbe]. Always reports
/// [AAudioProbeResult.unsupportedPlatform] — there is no AAudio on this
/// platform (web).
class NativeAAudioProbe {
  NativeAAudioProbe._();
  static final NativeAAudioProbe instance = NativeAAudioProbe._();

  AAudioProbeReport run() => const AAudioProbeReport(
    result: AAudioProbeResult.unsupportedPlatform,
    sharingMode: AAudioSharingMode.unknown,
    performanceMode: AAudioPerformanceMode.unknown,
    detail: 'AAudio hanya tersedia di Android',
  );
}
