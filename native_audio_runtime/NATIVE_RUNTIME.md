# native_audio_runtime — Phase 4 Native DSP Core

## What this package is

A standalone Dart/Flutter **FFI package** (`flutter create --template=package_ffi`)
that provides the music player's native DSP processing architecture.

**Phase 4 adds** on top of the Phase 3 runtime foundation:
- `AudioBuffer` — interleaved float32 PCM buffer abstraction (`audio_buffer.h/c`)
- `DspPipeline` — ordered processing chain (`dsp_pipeline.h/c`)
- `GainProcessor` — first concrete processor; validates the pipeline end-to-end (`gain_processor.h/c`)
- Dart facades: `NativeDspPipeline` singleton, `NativeAudioBuffer` wrapper

Media3 remains the **only active playback engine** in Phase 4 — the DSP pipeline
architecture is established and exercised by tests, but not yet wired into
Media3's audio thread. That integration is Phase 5+ work.

## Why a separate package, not code embedded in the main app

See Phase 3 rationale (still applies): official `package_ffi` convention,
native assets build hooks, reusability, testability. The Phase 4 C code adds
three new translation units but zero Gradle/CMake changes — all orchestrated
by the existing `hook/build.dart`.

## Public API

`package:native_audio_runtime/native_audio_runtime.dart` exports three singletons:

### `NativeAudioRuntime.instance`

| Member | Purpose |
|---|---|
| `initialize()` | Idempotent init of the shared native runtime. |
| `dispose()` | Idempotent teardown. |
| `isAvailable` / `isInitialized` | Whether native library loaded & initialized. |
| `version` | Native runtime version string (`"0.1.0-phase4"`). |
| `capabilities` | Capability list — **`dsp.pipeline` and `dsp.gain` are `supported: true`** in Phase 4. |
| `registerModule(id)` | Native-side module ledger. |
| `registeredModuleIds` | Ids registered so far. |

### `NativeDspPipeline.instance`

| Member | Purpose |
|---|---|
| `initialize()` | Init C pipeline + register gain processor. Idempotent. |
| `dispose()` | Dispose pipeline and all processors. |
| `isInitialized` | Whether the pipeline is ready. |
| `setGainDb(db)` | Set gain in dBFS (clamped to [-96, +24]). Thread-safe. |
| `gainDb` | Current gain in dBFS. |
| `setGainBypass(bool)` | Zero-copy bypass when `true`. Thread-safe. |
| `gainBypass` | Whether bypass is active. |
| `setProcessorEnabled(id, enabled:)` | Enable/disable a processor by its C id. Thread-safe. |
| `isProcessorEnabled(id)` | Whether the named processor is enabled. |
| `processorCount` | Number of registered processors (1 in Phase 4). |
| `processorIdAt(index)` | Processor id at `index` (e.g. `'dsp.gain'`). |
| `totalLatencyFrames` | Sum of processor latencies (0 in Phase 4). |
| `processBuffer(buf)` | Drive a buffer through the chain — primarily for testing. |
| `reset()` | Reset all processor states. |

### `NativeAudioBuffer`

| Member | Purpose |
|---|---|
| `create(...)` | Allocate an interleaved float32 PCM buffer. Returns `null` on failure. |
| `destroy()` | Free the native allocation (required — GC does not free it). |
| `data` | `Float32List` view directly into native memory — zero-copy. |
| `capacityFrames`, `frameCount`, `channelCount`, `sampleRate` | Metadata. |
| `setFrameCount(n)` | Narrow valid frame count without reallocating. |
| `timestampUs` / `setTimestampUs(us)` | Optional playback-position metadata. |
| `nativePointer` | Raw `Pointer<NarAudioBuffer>` for `processBuffer`. |

All types (`NativeRuntimeStatus`, `NativeRuntimeCapability`, `NativeRuntimeException`)
live in `lib/src/runtime_types.dart` — pure Dart, web-safe.

## Web safety

`dart:ffi` is unavailable on web. All three exported classes have stub
implementations (`*_unsupported.dart`) with identical APIs:
- `NativeAudioRuntime.isAvailable` → `false`
- `NativeDspPipeline.isInitialized` → `false`
- `NativeAudioBuffer.create(...)` → `null`
- All control methods → no-ops

The same `import` works on every target:
```dart
import 'package:native_audio_runtime/native_audio_runtime.dart';
```

## Native C API (Phase 4 additions)

### `audio_buffer.h/c`
- `NarAudioBuffer` opaque struct — single heap allocation, capacity/frame metadata
- `nar_audio_buffer_create()` / `nar_audio_buffer_destroy()`
- `nar_audio_buffer_data()` — direct float* pointer (no copy)
- Sample formats: `NAR_SAMPLE_FORMAT_FLOAT32` (implemented); `INT16` (declared, unimplemented placeholder)

### `dsp_pipeline.h/c`
- Fixed-size slot array (up to 16 processors)
- `_Atomic int32_t enabled` per slot — `set_enabled()` is thread-safe
- `process()` / `reset()` — audio-thread only (no locking)
- `register_internal()` — calls vtable→init(); a non-OK init aborts registration

### `dsp_processor.h`
- `NarDspProcessorVTable` — every future processor implements this exact struct
- `NarDspProcessorDescriptor` — {id, self, vtable}
- `self` is owned by the registering module, NOT the pipeline

### `gain_processor.h/c`
- Gain stored as IEEE 754 float bits in `_Atomic int32_t` (portable lock-free)
- Hot loop: `data[i] *= gain_linear` — SIMD-ready; compiler auto-vectorizes with NEON
- Bypass: true zero-copy (returns immediately without touching samples)
- No clipping at output

## DSP Pipeline architecture

```
Flutter UI
  ↓
AudioService
  ↓
PlaybackManager          ← setNativeGainDb(), setNativeGainBypass(), etc.
  ↓
NativeDspPipeline.instance   (Dart FFI facade)
  ↓
nar_dsp_pipeline_process()   (C — dsp_pipeline.c)
  ↓
GainProcessor.process()      (C — gain_processor.c)
  ↓
[future processors]
```

**Not yet wired**: Media3/ExoPlayer audio thread does not call
`nar_dsp_pipeline_process()` in Phase 4. That integration is Phase 5+ work.

## Threading model

| Function | Thread safety |
|---|---|
| `nar_dsp_pipeline_process()` | Single audio thread only |
| `nar_dsp_pipeline_reset()` | Single audio thread only |
| `nar_dsp_pipeline_set_enabled()` | Any thread (atomic) |
| `nar_gain_processor_set_gain_db()` | Any thread (atomic) |
| `nar_gain_processor_set_bypass()` | Any thread (atomic) |
| `nar_dsp_pipeline_register_internal()` | Mutex-guarded |
| `nar_dsp_pipeline_dispose()` | Mutex-guarded |

## Build hook

`hook/build.dart` now compiles four C sources:
```
src/native_audio_runtime.c   — lifecycle, version, capabilities, module registry
src/audio_buffer.c           — NarAudioBuffer
src/dsp_pipeline.c           — DSP chain
src/gain_processor.c         — Gain processor
```

## What was verified in this environment

1. **`flutter analyze` is clean** — no issues across the entire workspace.
2. **Web build succeeds** — `flutter build web` completes; `dart.library.ffi` stub path confirmed.
3. **Tests written** — `native_audio_runtime/test/native_audio_runtime_test.dart` covers all Phase 4 requirements. Note: running `dart test` locally requires the same `clang → gcc` symlink workaround documented in the Phase 3 section below (same environment constraint — no Android SDK/NDK).
4. **`analysis_options.yaml`** at workspace root now excludes `native_audio_runtime/test/**` from workspace-level analysis (the `test:` dev dependency of the sub-package is not in the workspace resolved set; run `dart test` from inside `native_audio_runtime/` to exercise those files).

## Remaining work before Parametric EQ (Phase 5)

1. **Wire DSP into Media3 audio thread** — implement `ExoPlayer`'s
   `AudioProcessor` interface to call `nar_dsp_pipeline_process()` per output
   buffer from `DefaultAudioSink`.
2. **Expose EQ controls** — implement `EqProcessor` (a `NarDspProcessorVTable`
   with per-band biquad filters); register after the gain processor.
3. **A/V sync** — use `nar_dsp_pipeline_total_latency_frames()` to compensate
   Media3's audio/video synchronization for any future latency-introducing
   processors.
4. **Confirm APK build** — verify `flutter build apk` invokes `hook/build.dart`
   for `android_arm64` and bundles the resulting `.so`; confirm
   `NativeDspPipeline.instance.isInitialized` is `true` on device.
5. **NEON optimization** — replace the gain processor's auto-vectorized loop
   with explicit `arm_neon.h` intrinsics; add a SIMD capability flag.

---

## Phase 3 Notes (still applicable)

### Why the environment has no Android NDK

This Replit sandbox has no Android SDK/NDK. `flutter doctor` reports the Android
toolchain missing. The `dart test` + `clang → gcc` symlink workaround still applies
for running tests on the host (Linux x64).

What remains unverified until an actual APK build:
- `flutter build apk` native-assets + AGP 9.0.1 interaction
- `.so` loading on a real device; `NativeDspPipeline.instance.isInitialized` on device
- `abiFilters arm64-v8a` respect by native-assets toolchain
