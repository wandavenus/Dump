# Native Bridges — Architecture & Integration Guide

## Overview

This directory (`lib/services/native/`) defines the **Dart-side foundation** for
pluggable native modules.  It establishes the pattern that all future C++-backed
features (DSP, FFmpeg, FFT analyser, etc.) must follow, without changing any
existing playback code.

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
- Future MethodChannel `musicplayer/native_dsp`
- C++ DSP: parametric EQ, compressor, resampler, spatial audio
- Does NOT replace Media3's `AudioEffect` API — it augments it
- **Status:** Stub (unavailable)

### FfmpegDecoderBridge
- Future MethodChannel `musicplayer/ffmpeg_decoder`
- Decodes formats ExoPlayer cannot handle natively (DSD, APE, high-res FLAC, WavPack)
- Also owns loudness scanning (EBU R128 via `ffmpeg -af loudnorm`)
- **Status:** Stub (unavailable)

---

## NativeModule Lifecycle

```
PlaybackManager.initialize()
    └─ NativeModuleRegistry.initializeAll()
           ├─ NativeDspBridge.initialize()        → unavailable (stub)
           └─ FfmpegDecoderBridge.initialize()    → unavailable (stub)

PlaybackManager.dispose()  [future — not yet called]
    └─ NativeModuleRegistry.disposeAll()
           ├─ FfmpegDecoderBridge.dispose()
           └─ NativeDspBridge.dispose()
```

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

When ready to implement `NativeDspBridge`:

1. **Android side**
   - Create `android/app/src/main/cpp/dsp/` with `CMakeLists.txt`.
   - Add `externalNativeBuild { cmake { path "src/main/cpp/CMakeLists.txt" } }` to `app/build.gradle`.
   - Implement JNI entry points (`Java_com_example_musicplayer_NativeDsp_*`).
   - OR use Dart FFI with a `.so` built by CMake.

2. **Dart side**
   - Replace stub method bodies in `NativeDspBridge` with `MethodChannel` or `DynamicLibrary` calls.
   - No changes needed in `PlaybackManager` or any service.

3. **Routing decision**
   - Android `AudioEffect` (bassboost/virtualizer): stay in `Media3PlaybackBridge` — OS-managed, session-aware.
   - Custom precision EQ / compressor / resampler: route through `NativeDspBridge`.

---

## FFmpeg Integration Strategy

When ready to implement `FfmpegDecoderBridge`:

1. **Dependency options (choose one)**
   - `ffmpeg_kit_flutter_audio` (pub.dev) — fastest, adds ~15 MB to APK.
   - Custom CMake build of FFmpeg in `android/app/src/main/cpp/ffmpeg/` — smallest, most control.

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
