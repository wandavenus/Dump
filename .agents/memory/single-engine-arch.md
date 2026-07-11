---
name: Single-engine architecture
description: media_kit dihapus total; satu-satunya engine adalah Media3/ExoPlayer; detail apa yang berubah dan stub compatibility.
---

## Aturan

Flutter UI → AudioService → AudioEngineManager → Media3PlaybackBridge → Media3PlaybackService.kt → ExoPlayer

Tidak ada multi-engine, tidak ada runtime switching, tidak ada abstract engine layer.

**Why:** Refactor untuk menghilangkan kompleksitas hybrid engine dan menjadikan Media3 sebagai satu-satunya sumber kebenaran.

**How to apply:**
- Jangan pernah tambahkan kembali `AbstractAudioEngine`, `PlaybackEngineType`, atau `switchEngine()`.
- `registerPostSwitchCallback(VoidCallback)` tetap ada di AudioEngineManager sebagai **no-op stub** — AudioEffectsService.init() masih memanggilnya; jangan hapus method-nya.
- `EngineEqualizerParameters` sekarang didefinisikan di `audio_engine_manager.dart` (bukan di `engine_abstraction.dart` yang sudah dihapus).

## File yang dihapus

### Dart
- `lib/services/audio/engine_abstraction.dart`
- `lib/services/audio/engines/media_kit_engine.dart`
- `lib/services/audio/engines/media3_engine.dart`
- `lib/services/audio/mediakit/mediakit_service_bridge.dart`
- `lib/services/audio/mediakit/mediakit_settings_service.dart`
- `lib/pages/settings_page/mediakit_audio.dart`
- `test/media3_engine_test.dart`

### Android (Kotlin)
- `MediaKitPlaybackService.kt`
- `MediaKitEventEmitter.kt`
- `MediaKitStatePlayer.kt`

### pubspec.yaml
- `media_kit: ^1.2.6`
- `media_kit_libs_android_audio: ^1.3.8`

## Titik extension untuk masa depan

Native C++ DSP / FFmpeg decoder → tambahkan sebagai slot terpisah di `Media3PlaybackBridge` atau bridge baru, **jangan** buat abstract engine layer lagi.
