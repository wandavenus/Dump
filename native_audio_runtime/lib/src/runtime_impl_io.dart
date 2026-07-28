/// Real `dart:ffi`-backed implementation, used on every platform where
/// `dart:ffi` is available (Android, iOS, Linux, macOS, Windows). Selected
/// automatically by the conditional export in `native_audio_runtime.dart` —
/// never import this file directly.
library;

import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart' as pkg_ffi;

import '../native_audio_runtime_bindings_generated.dart' as bindings;
import 'runtime_types.dart';

class NativeAudioRuntime {
  NativeAudioRuntime._();

  static final NativeAudioRuntime instance = NativeAudioRuntime._();

  bool _initialized = false;

  /// Whether the native runtime successfully initialized on this device.
  /// False if [initialize] was never called, or the native call reported
  /// anything other than [NativeRuntimeStatus.ok] /
  /// [NativeRuntimeStatus.alreadyInitialized].
  bool get isAvailable => _initialized;

  bool get isInitialized => bindings.native_runtime_is_initialized() != 0;

  /// Initialize the shared native runtime. Safe to call more than once —
  /// subsequent calls observe [NativeRuntimeStatus.alreadyInitialized] and
  /// are treated as success, matching the native idempotency contract.
  Future<void> initialize() async {
    final code = bindings.native_runtime_init();
    final status = NativeRuntimeStatus.fromCode(code);
    switch (status) {
      case NativeRuntimeStatus.ok:
      case NativeRuntimeStatus.alreadyInitialized:
        _initialized = true;
        return;
      default:
        _initialized = false;
        throw NativeRuntimeException('initialize', status);
    }
  }

  /// Tear down the native runtime. Safe to call even if never initialized.
  Future<void> dispose() async {
    final code = bindings.native_runtime_dispose();
    final status = NativeRuntimeStatus.fromCode(code);
    _initialized = false;
    if (status != NativeRuntimeStatus.ok) {
      throw NativeRuntimeException('dispose', status);
    }
  }

  /// Native runtime version string (e.g. `'0.1.0-phase3'`).
  String get version {
    final ptr = bindings.native_runtime_get_version();
    if (ptr == ffi.nullptr) return 'unknown';
    return ptr.cast<pkg_ffi.Utf8>().toDartString();
  }

  /// Snapshot of every capability the runtime currently knows about.
  /// Phase 3: all entries report `supported: false` — placeholders only.
  List<NativeRuntimeCapability> get capabilities {
    final count = bindings.native_runtime_capability_count();
    return List.generate(count, (i) {
      final keyPtr = bindings.native_runtime_capability_key(i);
      final key = keyPtr == ffi.nullptr
          ? 'unknown'
          : keyPtr.cast<pkg_ffi.Utf8>().toDartString();
      final supported = bindings.native_runtime_capability_supported(i) != 0;
      return NativeRuntimeCapability(key: key, supported: supported);
    });
  }

  /// Register a logical module id with the native runtime. Returns the
  /// resulting [NativeRuntimeStatus] rather than throwing, since a duplicate
  /// registration is an expected, recoverable outcome for callers (e.g. a
  /// bridge re-registering after a hot restart).
  NativeRuntimeStatus registerModule(String moduleId) {
    final idPtr = pkg_ffi.StringUtf8Pointer(moduleId).toNativeUtf8();
    try {
      final code = bindings.native_runtime_register_module(idPtr.cast());
      return NativeRuntimeStatus.fromCode(code);
    } finally {
      pkg_ffi.calloc.free(idPtr);
    }
  }

  /// Ids of every module registered so far, in registration order.
  List<String> get registeredModuleIds {
    final count = bindings.native_runtime_module_count();
    return List.generate(count, (i) {
      final ptr = bindings.native_runtime_module_id_at(i);
      return ptr == ffi.nullptr
          ? 'unknown'
          : ptr.cast<pkg_ffi.Utf8>().toDartString();
    });
  }
}

// ── NativeAAudioProbe ─────────────────────────────────────────────────────────

/// Dart facade over the native AAudio capability probe
/// (`src/aaudio_probe.h`). Diagnostic-only — not part of the DSP pipeline,
/// no lifecycle/registration step needed.
///
/// Answers "what does this device actually grant?" for AAudio exclusive
/// mode / MMAP, which cannot be determined from static device info: it
/// opens a real stream requesting exclusive + low-latency, reads back what
/// AAudio actually handed back, then closes it immediately.
class NativeAAudioProbe {
  NativeAAudioProbe._();
  static final NativeAAudioProbe instance = NativeAAudioProbe._();

  /// Run one probe. Safe to call repeatedly — each call opens and closes a
  /// fresh, short-lived stream; does not interfere with playback.
  AAudioProbeReport run() {
    final code = bindings.native_runtime_aaudio_probe();
    final result = AAudioProbeResult.fromCode(code);

    final sharingCode = bindings.native_runtime_aaudio_last_sharing_mode();
    final sharingMode = switch (sharingCode) {
      0 => AAudioSharingMode.exclusive,
      1 => AAudioSharingMode.shared,
      _ => AAudioSharingMode.unknown,
    };

    final perfCode = bindings.native_runtime_aaudio_last_performance_mode();
    final performanceMode = switch (perfCode) {
      10 => AAudioPerformanceMode.none,
      11 => AAudioPerformanceMode.powerSaving,
      12 => AAudioPerformanceMode.lowLatency,
      _ => AAudioPerformanceMode.unknown,
    };

    final errPtr = bindings.native_runtime_aaudio_last_error();
    final detail = errPtr == ffi.nullptr
        ? ''
        : errPtr.cast<pkg_ffi.Utf8>().toDartString();

    return AAudioProbeReport(
      result: result,
      sharingMode: sharingMode,
      performanceMode: performanceMode,
      detail: detail,
    );
  }
}
