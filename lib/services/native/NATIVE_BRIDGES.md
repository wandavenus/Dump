# Native Bridges — Architecture & Integration Guide

## Overview

This directory (`lib/services/native/`) defines the **Dart-side foundation** for
pluggable native modules.  It establishes the pattern that all future C++-backed
features (DSP, FFmpeg, FFT analyser, etc.) must follow, without changing any
existing playback code.

**Phase 3 update:** `NativeDspBridge` and `FfmpegDecoderBridge` now talk to a
real, shared native runtime via `dart:ffi` — the standalone
`native_audio_runtime` package (see its own `NATIVE_RUNTIME.md` for the full
architecture, native C API, thread-safety design, and — importantly — which
parts of this could and could not be verified in this environment, since no
Android SDK/NDK is installed here). Kotlin stays scoped to Android-framework
concerns only (Media3, notifications, Bluetooth, etc.) per this phase's
explicit design; DSP/FFmpeg are never routed through Kotlin/JNI.

---

## Directory Structure

```
lib/services/native/
├── contracts/
│   └── native_module.dart          NativeModule abstract interface + NativeCapability
├── models/
│   └── native_module_status.dart   NativeModuleStatus enum
├── bridges/
│   ├── native_dsp_bridge.dart      NativeDspBridge  — C++ DSP stub
│   └── ffmpeg_decoder_bridge.dart  FfmpegDecoderBridge — FFmpeg stub
├── native_module_registry.dart     Central module registry
└── NATIVE_BRIDGES.md               This file
```

---

## Ownership Rules

```
Flutter UI
    │  (read-only — PlaybackManager getters only)
    ▼
AudioService
    │  (PlaybackManager public API only)
    ▼
PlaybackManager  ◄─── single entry point for ALL native access
    ├── Media3PlaybackBridge   (active — ExoPlayer)
    ├── NativeDspBridge        (stub — future C++ DSP)
    └── FfmpegDecoderBridge    (stub — future FFmpeg)
           │
           ▼
    NativeModuleRegistry  (lifecycle manager)
```

**Rule:** UI and services never import from `lib/services/native/bridges/` directly.
All native access goes through `PlaybackManager`.

---

## Bridge Responsibilities

### Media3PlaybackBridge
- MethodChannel `musicplayer/playback`
- All transport, queue, repeat/shuffle, DSP effects (Android `AudioEffect` API)
- **Status:** Active

### NativeDspBridge
- `dart:ffi` via `package:native_audio_runtime` (shared runtime singleton)
- C++ DSP: parametric EQ, compressor, resampler, spatial audio
- Does NOT replace Media3's `AudioEffect` API — it augments it
- **Status:** Runtime available (real init/version/capability round-trip) — no DSP algorithm implemented yet

### FfmpegDecoderBridge
- `dart:ffi` via `package:native_audio_runtime` (shared runtime singleton)
- Decodes formats ExoPlayer cannot handle natively (DSD, APE, high-res FLAC, WavPack)
- Also owns loudness scanning (EBU R128 via `ffmpeg -af loudnorm`)
- **Status:** Runtime available (real init/version/capability round-trip) — FFmpeg itself not bundled yet

---

## NativeModule Lifecycle

```
PlaybackManager.initialize()   [called once, from main.dart]
    └─ NativeModuleRegistry.initializeAll()
           ├─ NativeDspBridge.initialize()        → NativeAudioRuntime.instance.initialize()
           │                                          (idempotent — shared singleton)
           │                                        → registerModule('native_dsp')
           └─ FfmpegDecoderBridge.initialize()    → NativeAudioRuntime.instance.initialize()
                                                       (2nd call → ALREADY_INITIALIZED, treated as ok)
                                                     → registerModule('ffmpeg_decoder')

PlaybackManager.dispose()      [implemented — not yet wired to an app-lifecycle hook]
    └─ NativeModuleRegistry.disposeAll()
           ├─ FfmpegDecoderBridge.dispose()   → marks module disposed (runtime itself untouched)
           └─ NativeDspBridge.dispose()       → marks module disposed (runtime itself untouched)
```

Note: neither bridge calls `NativeAudioRuntime.instance.dispose()` — the
runtime is a shared singleton and either bridge disposing it would break the
other while it's still registered. It's disposed once, if ever, by whichever
higher-level shutdown path is added later (not currently wired to an
app-lifecycle hook, matching `PlaybackManager.dispose()`'s own status).

`PlaybackManager.nativeModules` and `PlaybackManager.queryNativeCapabilities()` expose
read-only access to the registry for debug UIs — the only sanctioned way to inspect
native module state from outside this directory.

---

## Adding a New Native Module

1. Create `lib/services/native/bridges/my_module_bridge.dart` implementing `NativeModule`.
2. Register in `PlaybackManager.initialize()`:
   ```dart
   NativeModuleRegistry.register(MyModuleBridge.instance);
   ```
3. Add public accessor(s) on `PlaybackManager` — not on the bridge itself.
4. Implement the Android side (Kotlin `MethodChannel` handler or JNI).

Planned future modules:

| Module ID           | Class                  | Purpose                         |
|---------------------|------------------------|---------------------------------|
| `native_dsp`        | NativeDspBridge        | C++ parametric DSP              |
| `ffmpeg_decoder`    | FfmpegDecoderBridge    | Extended format decoding        |
| `fft_analyser`      | (future)               | Real-time spectrum data         |
| `audio_visualizer`  | (future)               | Waveform / VU meter             |
| `loudness_analyser` | (future)               | EBU R128 offline scan           |
| `resampler`         | (future)               | High-quality SRC                |

---

## C++ DSP Integration Strategy

When ready to implement real DSP (Phase 4+):

1. **Native side (in `native_audio_runtime/`, not `android/app/src/main/cpp/`)**
   - Add new `.c`/`.h` source files alongside `src/native_audio_runtime.c`.
   - Add their sources to `hook/build.dart`'s `CBuilder.library(sources: [...])` list.
   - Keep DSP math out of Kotlin entirely — Dart FFI only, per this phase's design.

2. **Dart side**
   - Extend `NativeAudioRuntime` (or add a dedicated binding set in
     `native_audio_runtime`) with the new calls.
   - Replace the `TODO(phase-dsp)` method bodies in `NativeDspBridge` — its
     public method signatures are already locked for this.
   - No changes needed in `PlaybackManager` or any other service.

3. **Routing decision**
   - Android `AudioEffect` (bassboost/virtualizer): stay in `Media3PlaybackBridge` — OS-managed, session-aware.
   - Custom precision EQ / compressor / resampler: route through `NativeDspBridge`.

---

## FFmpeg Integration Strategy

When ready to implement `FfmpegDecoderBridge`:

1. **Dependency options (choose one)**
   - `ffmpeg_kit_flutter_audio` (pub.dev) — fastest, adds ~15 MB to APK.
   - Custom build of FFmpeg wired into `native_audio_runtime/hook/build.dart`
     (native assets) — smallest, most control, keeps FFmpeg out of Kotlin.

2. **Decoder registration**
   - In `Media3PlaybackService.kt`, override `buildRenderersFactory()`.
   - Inject an `FfmpegAudioRenderer` for formats not covered by MediaCodec.
   - `FfmpegDecoderBridge.canDecodeFormat()` gates the registration at runtime.

3. **Loudness scanning**
   - `FfmpegDecoderBridge.scanLoudness(filePath)` calls FFmpeg EBU R128 filter.
   - Results feed into `ReplayGainService` / `MetadataCacheDb`.
   - Replaces current ExoPlayer `MetadataRetriever`-based scan for formats it misses.

4. **Dart side**
   - Replace stub bodies in `FfmpegDecoderBridge`.
   - Wire `canDecodeFormat()` into `MediaStoreService` format probing if needed.
   - No changes to `PlaybackManager` public API.
