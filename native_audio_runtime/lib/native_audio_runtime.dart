/// Native audio runtime — Phase 4/5 DSP pipeline.
///
/// Public API:
/// - [NativeAudioRuntime]  — singleton facade: lifecycle, version, capabilities.
/// - [NativeDspPipeline]   — pipeline facade: gain, enable/disable processors.
/// - [NativeParametricEq]  — Phase 5: 32-band parametric EQ facade.
/// - [PeqFilterType]       — Phase 5: filter topology enum for [NativeParametricEq].
/// - [NativeAudioBuffer]   — interleaved float32 PCM buffer (primarily for tests).
///
/// Platform note: the real implementations require `dart:ffi`, unavailable on
/// web. This file conditionally exports FFI-backed implementations on every
/// platform that has `dart:ffi` (Android, iOS, Linux, macOS, Windows) and
/// pure-Dart stubs on web, so the SAME import works unconditionally from app
/// code on every target this project builds for.
library;

export 'src/runtime_types.dart';
export 'src/runtime_impl_unsupported.dart'
    if (dart.library.ffi) 'src/runtime_impl_io.dart';
export 'src/dsp_pipeline_unsupported.dart'
    if (dart.library.ffi) 'src/dsp_pipeline_io.dart';
