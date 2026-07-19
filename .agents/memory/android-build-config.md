---
name: Android Build Config & Manifest
description: AndroidManifest permissions/services, build.gradle SDK versions, NDK/CMake, CMakeLists targets, ProGuard rules.
---

# Android Build Config & Manifest

## AndroidManifest.xml

**Permissions declared:**
- `READ_EXTERNAL_STORAGE` / `READ_MEDIA_AUDIO` (runtime, Android 13+)
- `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_MEDIA_PLAYBACK`
- `WAKE_LOCK`
- `RECEIVE_BOOT_COMPLETED`
- `MEDIA_CONTENT_CONTROL`
- `MODIFY_AUDIO_SETTINGS`

**Services:**
- `Media3PlaybackService` — foreground service, `stopWithTask=false`, `MEDIA_BUTTON` intent filter
- No other declared services

**Activities:**
- `MainActivity` — handles external file open intents (`ACTION_VIEW` for audio MIME types)

**Metadata:**
- `com.google.android.gms.car.application` (Android Auto support entry)

**Key intent filters:**
- `MainActivity`: `ACTION_MAIN` + `CATEGORY_LAUNCHER`, `ACTION_VIEW` for audio files
- `Media3PlaybackService`: `MEDIA_BUTTON`

## build.gradle (app)

| Setting | Value |
|---------|-------|
| `compileSdk` | 35 |
| `minSdk` | 29 (Android 10) |
| `targetSdk` | 35 |
| NDK version | (current stable, check file for exact) |
| CMake version | 3.22+ |
| `abiFilters` | `arm64-v8a` only (Mi 9T target) |

**Build types:**
- `debug` — standard
- `release` — R8/ProGuard enabled; `shrinkResources true`

**CMake config:**
```gradle
externalNativeBuild {
  cmake {
    path "src/main/cpp/CMakeLists.txt"
    arguments "-DANDROID_STL=c++_shared"
  }
}
```

## CMakeLists.txt (android/app/src/main/cpp/)

### Target: `replaygain_native`
**Sources:**
- `libebur128/` — EBU R128 loudness measurement C library
- `taglib/` — TagLib C++ tag reading/writing
- JNI wrapper: `replaygain_jni.cpp`

**Links:** `log`, `android`

**Notes:** M4A write unsupported by design. Tag writes use temp-file + atomic-rename.

### Target: `stretch_native`
**Sources:**
- `signalsmith-stretch/` — STFT-based time-stretch/pitch-shift
- `signalsmith-dsp/` — FFT/STFT linear algebra (Signalsmith Linear)
- JNI wrapper: `stretch_jni.cpp`

**Links:** `log`, `android`

**JNI functions exposed:**
- `Java_dev_wndavenz_music_replaygain_ReplayGainNative_*` — scan, tag-write, get-gain
- Stretch JNI functions for time-ratio, pitch-shift control

## ProGuard / R8 Rules

Key keeps:
- All JNI-called Java/Kotlin classes (tagged with `-keep`)
- `Media3PlaybackService`, `MainActivity`
- Native method signatures: `dev.wndavenz.music.replaygain.ReplayGainNative`
