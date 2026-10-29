# Native Bridges — Architecture & Integration Guide

## Overview

This directory (`lib/services/native/`) defines the **Dart-side foundation** for
pluggable native modules.  It establishes the pattern that all future C++-backed
features (DSP, FFmpeg, FFT analyser, etc.) must follow, without changing any
existing playback code.

**Phase 3 update:** `NativeDspBridge` talks to a real, shared native runtime
via `dart:ffi` — the standalone `native_audio_runtime` package (see its own
`NATIVE_RUNTIME.md` for the full architecture, native C API, thread-safety
design, and — importantly — which parts of this could and could not be
verified in this environment, since no Android SDK/NDK is installed here).
Kotlin stays scoped to Android-framework concerns only (Media3, notifications,
Bluetooth, etc.) for DSP; DSP is never routed through Kotlin/JNI.

**Phase 9 update:** `FfmpegDecoderBridge` no longer uses `native_audio_runtime`
FFI at all. Decoding for formats Media3 can demux but can't decode natively
(ALAC, DTS, TrueHD, Vorbis edge cases; Opus uses platform MediaCodec) is handled
by Media3's FFmpeg extension (`FfmpegAudioRenderer`), built locally as the
`:decoder-ffmpeg` Android module and running inside `Media3PlaybackService.kt`'s
ExoPlayer instance. `FfmpegDecoderBridge` is now a Kotlin/JNI bridge (its own small
MethodChannel + EventChannel pair) rather than an FFI bridge. The native
library (`libffmpegJNI.so`) is compiled by `android/build-ffmpeg-jni.sh` from
FFmpeg source with `--disable-gpl`; the former Jellyfin prebuilt AAR (GPL v3)
is no longer used. `native_audio_runtime` remains exclusively the DSP runtime;
it was not touched by this phase.

---

## Directory Structure

```
lib/services/native/
├── contracts/
│   └── native_module.dart          NativeModule abstract interface + NativeCapability
├── models/
│   └── native_module_status.dart   NativeModuleStatus enum
├── bridges/
│   ├── native_dsp_bridge.dart      NativeDspBridge  — C++ DSP stub (FFI)
│   └── ffmpeg_decoder_bridge.dart  FfmpegDecoderBridge — local FFmpeg JNI extension (Kotlin/JNI, own channel pair)
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
    ├── NativeDspBridge        (stub — future C++ DSP, FFI)
    └── FfmpegDecoderBridge    (active — local FFmpeg JNI extension, Kotlin/JNI)
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
- Own MethodChannel `musicplayer/ffmpeg_decoder` (capability query) + EventChannel
  `musicplayer/ffmpeg_decoder_events` (per-track decoder selection diagnostics)
- Decoding itself happens inside ExoPlayer via the local `:decoder-ffmpeg`
  module (Media3 wrapper + `libffmpegJNI.so`) — Dart never touches raw
  audio; this bridge only reports status
- Covers (Phase 9 scope): ALAC, DTS/DTS-HD, TrueHD, Vorbis edge cases —
  formats Media3 can demux but has no on-device MediaCodec decoder for.
  Opus is excluded because the platform MediaCodec/CCodec decoder handles it
- Out of scope: APE, WavPack, TAK, Monkey's Audio (no Media3 container
  `Extractor` exists for these at all — separate, larger follow-up)
- **Status:** Architecture + real code complete. `libffmpegJNI.so` is built
  from FFmpeg source by `android/build-ffmpeg-jni.sh`; `FfmpegLibrary.isAvailable()`
  reports whether it loaded on the device, and ExoPlayer falls back to platform
  MediaCodec when it does not.

---

## NativeModule Lifecycle

```
PlaybackManager.initialize()   [called once, from main.dart]
    └─ NativeModuleRegistry.initializeAll()
           ├─ NativeDspBridge.initialize()        → NativeAudioRuntime.instance.initialize()
           │                                          (idempotent — shared singleton)
           │                                        → registerModule('native_dsp')
           └─ FfmpegDecoderBridge.initialize()    → MethodChannel('musicplayer/ffmpeg_decoder')
                                                       .invokeMethod('queryStatus')
                                                     → subscribes to the ffmpeg_decoder_events
                                                       EventChannel for the lifetime of the app

PlaybackManager.dispose()      [implemented — not yet wired to an app-lifecycle hook]
    └─ NativeModuleRegistry.disposeAll()
           ├─ FfmpegDecoderBridge.dispose()   → cancels its event subscription
           └─ NativeDspBridge.dispose()       → marks module disposed (runtime itself untouched)
```

Note: `NativeDspBridge` never calls `NativeAudioRuntime.instance.dispose()` —
it is the sole remaining user of the shared FFI runtime singleton as of
Phase 9 (`FfmpegDecoderBridge` no longer touches it at all), but the runtime
is still disposed only by a higher-level shutdown path if one is added later
(not currently wired to an app-lifecycle hook, matching
`PlaybackManager.dispose()`'s own status).

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
| `ffmpeg_decoder`    | FfmpegDecoderBridge    | Extended format decoding (ALAC/DTS/TrueHD/Vorbis); Opus uses platform MediaCodec |
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
   - Android `AudioEffect` (bassboost): stay in `Media3PlaybackBridge` — OS-managed, session-aware.
   - Custom precision EQ / compressor / resampler: route through `NativeDspBridge`.

---

## FFmpeg Decoder Integration (Phase 9 — implemented)

Summary:

- Media3's FFmpeg extension wrapper (`FfmpegAudioRenderer`, Apache 2.0) is
  vendored in `android/decoder-ffmpeg/` and linked against a locally built
  `libffmpegJNI.so` — never `ffmpeg_kit_flutter` and never the Jellyfin GPL AAR.
  `DefaultRenderersFactory`'s `EXTENSION_RENDERER_MODE_PREFER` +
  `setEnableDecoderFallback(true)` makes ExoPlayer prefer the extension and
  fall back to platform MediaCodec automatically when it is unavailable —
  **no `RenderersFactory` code changes were needed for this phase.**
- The module is part of the normal Gradle build (`include ":decoder-ffmpeg"`),
  not an optional flag. `android/build-ffmpeg-jni.sh` cross-compiles FFmpeg
  `n8.1.3` for arm64-v8a with `--disable-gpl --disable-nonfree
  --disable-version3` (LGPL-2.1-or-later) and the `preBuild` task runs it on
  first use. Generated artifacts stay under `.ffmpeg-build/` and `jniLibs/`.
- `FfmpegCapabilityProbe.kt` looks up `FfmpegLibrary` by reflection, so
  `Media3PlaybackService.kt` compiles even if the module is removed and a
  missing/unloadable library collapses to `available = false`.
- PCM from `FfmpegAudioRenderer` flows through the exact same
  `NativeDspAudioProcessor` chain as any built-in decoder — DSP pipeline
  unchanged.
- Scope: ALAC, DTS/DTS-HD, TrueHD, Vorbis only (Opus uses platform MediaCodec).
  APE/WavPack/TAK/Monkey's Audio need a custom `Extractor` (no container demuxer
  exists for them in Media3) and are a separate, larger follow-up — not attempted here.
