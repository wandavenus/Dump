---
name: Repo Architecture Overview
description: Top-level directory layout and layer responsibilities for the Flutter music player app.
---

# Repo Architecture Overview

## Top-Level Structure

| Folder | Purpose |
|--------|---------|
| `lib/` | Flutter/Dart UI + services layer |
| `android/` | Native Android: Media3/ExoPlayer, Kotlin services, JNI/CMake |
| `native_audio_runtime/` | Standalone C DSP engine (FFI package, also used via JNI on Android) |
| `assets/` | Fonts, shaders, images |
| `docs/` / `Audit/` | Architecture docs, performance audit reports |
| `pubspec.yaml` | Flutter deps, version (currently 1.3.4) |

## Layer Stack (top → bottom)

```
Flutter UI (lib/pages/, lib/widgets/)
        ↓
Dart Services (lib/services/)
        ↓ MethodChannel / EventChannel
Kotlin Android Layer (android/app/src/main/kotlin/)
        ↓ JNI
native_audio_runtime C DSP (native_audio_runtime/src/)
        ↓
Android AudioTrack / AAudio hardware output
```

## Key Invariants
- Single audio engine: Media3/ExoPlayer only (media_kit removed)
- Native owns queue, shuffle, repeat, sleep timer — Dart is EventChannel consumer
- DSP pipeline runs in C via JNI, not in Kotlin or Dart
- Target device ONLY: Xiaomi Mi 9T / Snapdragon 730 / MIUI 12 Android 11
