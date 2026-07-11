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
(ALAC, DTS, TrueHD, Vorbis/Opus edge cases) is handled entirely by Google's own
official `androidx.media3:media3-decoder-ffmpeg` extension, running inside
`Media3PlaybackService.kt`'s ExoPlayer instance. `FfmpegDecoderBridge` is now a
Kotlin/JNI bridge (its own small MethodChannel + EventChannel pair) rather than
an FFI bridge — see `docs/PHASE_9_FFMPEG_DECODER_INTEGRATION.md` for the full
design and why `ffmpeg_kit_flutter` (retired Jan/Apr 2025) was rejected.
`native_audio_runtime` remains exclusively the DSP runtime; it was not
touched by this phase.

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
│   └── ffmpeg_decoder_bridge.dart  FfmpegDecoderBridge — Media3 FFmpeg extension (Kotlin/JNI, own channel pair)
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
    └── FfmpegDecoderBridge    (active — Media3 FFmpeg extension, Kotlin/JNI)
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
- Decoding itself happens inside ExoPlayer via the official
  `androidx.media3:media3-decoder-ffmpeg` extension — Dart never touches raw
  audio; this bridge only reports status
- Covers (Phase 9 scope): ALAC, DTS/DTS-HD, TrueHD, Vorbis, Opus edge cases —
  formats Media3 can demux but has no on-device MediaCodec decoder for
- Out of scope: APE, WavPack, TAK, Monkey's Audio (no Media3 container
  `Extractor` exists for these at all — separate, larger follow-up)
- **Status:** Architecture + real code complete; native `.so` not vendored in
  this environment (no Android NDK) — `isAvailable` is `false` until someone
  completes the build in `docs/PHASE_9_FFMPEG_DECODER_INTEGRATION.md` and sets
  `ffmpegDecoderEnabled=true`

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
| `ffmpeg_decoder`    | FfmpegDecoderBridge    | Extended format decoding (ALAC/DTS/TrueHD/Vorbis/Opus) |
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

## FFmpeg Decoder Integration (Phase 9 — implemented)

Full design, rejected alternatives (`ffmpeg_kit_flutter*` — retired Jan/Apr
2025), the reflection-based capability probe, Gradle wiring, and the human
runbook for vendoring the actual `.so` on a machine with an Android NDK all
live in **`docs/PHASE_9_FFMPEG_DECODER_INTEGRATION.md`**. Summary:

- Media3's own `androidx.media3:media3-decoder-ffmpeg` extension
  (`FfmpegAudioRenderer`) is used — never `ffmpeg_kit_flutter` or a custom
  CMake build. `DefaultRenderersFactory`'s `EXTENSION_RENDERER_MODE_ON` +
  `setEnableDecoderFallback(true)` (already present in
  `Media3PlaybackService.kt` from an earlier phase) makes ExoPlayer try
  built-in decoders first and fall back to the extension automatically —
  **no `RenderersFactory` code changes were needed for this phase.**
- The module isn't on Maven Central; it's vendored as an optional local
  Gradle module (`android/decoder-ffmpeg/`, guarded in `settings.gradle` +
  `build.gradle` behind `ffmpegDecoderEnabled` in `local.properties`) so a
  build with the module absent still succeeds.
- `FfmpegCapabilityProbe.kt` looks up `FfmpegLibrary` by reflection, so
  `Media3PlaybackService.kt` compiles whether or not the module is present.
- PCM from `FfmpegAudioRenderer` flows through the exact same
  `NativeDspAudioProcessor` chain as any built-in decoder — DSP pipeline
  unchanged.
- Scope: ALAC, DTS/DTS-HD, TrueHD, Vorbis, Opus only. APE/WavPack/TAK/Monkey's
  Audio need a custom `Extractor` (no container demuxer exists for them in
  Media3) and are a separate, larger follow-up — not attempted here.
