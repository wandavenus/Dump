---
name: Single-engine architecture
description: media_kit dihapus total; satu-satunya engine adalah Media3/ExoPlayer; detail apa yang berubah dan stub compatibility.
---

## Arsitektur saat ini (setelah Phase 1 + Phase 2)

```
Flutter UI
  ↓
AudioService          — business-logic facade (lib/services/audio_service.dart)
  ↓
PlaybackManager       — stream routing + artwork prefetch (lib/services/audio/playback_manager.dart)
  ↓
Media3PlaybackBridge  — sole MethodChannel / EventChannel edge
  ↓
Media3PlaybackService.kt → ExoPlayer
```

**DeviceDsp** (`lib/services/audio/device_dsp.dart`) — DSP capability inspector (virtualizerSupported, bassBoostSupported) + loudness routing. Bukan bagian dari pipeline playback utama.

## Aturan

**Why:** Refactor untuk menghilangkan kompleksitas hybrid engine dan menjadikan Media3 sebagai satu-satunya sumber kebenaran.

**How to apply:**
- Jangan pernah tambahkan kembali `AbstractAudioEngine`, `PlaybackEngineType`, atau `switchEngine()`.
- Tidak ada `registerPostSwitchCallback` — sudah dihapus total (Phase 2). AudioEffectsService tidak lagi memanggilnya.
- `EqualizerParameters` didefinisikan di `playback_manager.dart`.
- Nama kelas tidak boleh mengandung "Engine" yang menyiratkan multi-engine — gunakan PlaybackManager, DeviceDsp, Media3PlaybackBridge.

## File lama yang sudah dihapus

- `audio_engine_manager.dart` → diganti `playback_manager.dart`
- `audio_engine.dart` + `audio_engine/engine.dart` → diganti `device_dsp.dart`
- `engine_abstraction.dart`, `engines/media_kit_engine.dart`, `engines/media3_engine.dart`
- `mediakit/` directory (service_bridge + settings_service)
- `MediaKitPlaybackService.kt`, `MediaKitEventEmitter.kt`, `MediaKitStatePlayer.kt`
- `media_kit` + `media_kit_libs_android_audio` dari pubspec.yaml

## Titik extension untuk masa depan

Native C++ DSP / FFmpeg decoder → tambahkan sebagai slot terpisah di `Media3PlaybackBridge` atau bridge baru, **jangan** buat abstract engine layer lagi.
