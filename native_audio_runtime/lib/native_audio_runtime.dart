/// Phase 3 native runtime foundation.
///
/// Public API: [NativeAudioRuntime] is a singleton facade over the native
/// runtime library (see `src/native_audio_runtime.h`/`.c`). It reports
/// lifecycle state, a static version string, and a placeholder capability
/// list — no DSP or FFmpeg processing exists yet (see `NATIVE_RUNTIME.md`).
///
/// Platform note: the real implementation requires `dart:ffi`, which is not
/// available when compiling for web. This file conditionally exports the
/// FFI-backed implementation on every platform that has `dart:ffi`
/// (Android, iOS, Linux, macOS, Windows) and a pure-Dart stub — always
/// reporting `isAvailable == false` — on web, so the SAME import works
/// unconditionally from app code on every target this project builds for.
library;

export 'src/runtime_types.dart';
export 'src/runtime_impl_unsupported.dart'
    if (dart.library.ffi) 'src/runtime_impl_io.dart';
