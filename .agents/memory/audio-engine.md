---
name: AudioEngine architecture
description: Layer baru audio system — AudioEngine (DSP pipeline) → AudioEffectsService (semua DSP control) → AudioService (playback facade). AudioSettingsService adalah shim kompatibilitas.
---

## Layer Stack

```
AudioEngine          lib/services/audio/audio_engine.dart
  └─ creates AudioPlayer with AndroidEqualizer + AndroidLoudnessEnhancer pipeline (Android only)
  └─ broadcasts androidAudioSessionId ke native via MethodChannel musicplayer/audio_effects

AudioEffectsService  lib/services/audio/audio_effects_service.dart
  └─ manages EQ, normalize, crossfade, pitch, speed, bass boost, reverb, spatial audio
  └─ persists semua settings ke SharedPreferences
  └─ built-in eq presets (Normal, Classical, Dance, Folk, Heavy Metal, Hip-Hop, Jazz, Pop, Rock)

CrossfadeController  lib/services/audio/crossfade_controller.dart
  └─ 50ms timer, fade-out saat remaining < crossfadeDuration, fade-in setelah skip

AudioSessionHandler  lib/services/audio/audio_session_handler.dart
  └─ package audio_session; configures AudioSessionConfiguration.music()
  └─ handles: interruptionEventStream, becomingNoisyEventStream

AudioService         lib/services/audio_service.dart
  └─ facade; pakai AudioEngine.player, integrate CrossfadeController
  └─ expose AudioService.player getter untuk backward compat
  └─ tambah loopMode, shuffleEnabled, speed ke AudioPlaybackState

AudioSettingsService lib/services/audio_settings_service.dart
  └─ SHIM ONLY — semua delegate ke AudioEffectsService; jangan hapus (masih dipakai banyak widget)
```

## Init Order (main.dart)
```dart
AudioEngine.initialize();           // 1st — buat player
await AudioEffectsService.init();   // 2nd — load prefs, apply effects
AudioService.initialize();          // 3rd — subscribe streams
AudioFocusService.initialize();     // 4th — setup audio session
```

## Android Native Effects (MainActivity.kt)
- Channel: `musicplayer/audio_effects`
- Methods: `attachEffects(sessionId)`, `setSpatialEnabled(enabled)`, `setBassBoost(strength 0-1000)`, `setReverb(preset 0-6)`
- Effects: Android `Virtualizer`, `BassBoost`, `PresetReverb` — harus `attachEffects` dulu baru yang lain bisa dipakai

**Why:** just_audio hanya wrap AndroidEqualizer + AndroidLoudnessEnhancer. Virtualizer/BassBoost/PresetReverb perlu native AudioEffect API langsung di Kotlin.

**How to apply:** Setiap kali ada fitur baru yang butuh Android AudioEffect, tambah method baru di `musicplayer/audio_effects` channel di MainActivity.kt dan panggil via `AudioEngine._effectsChannel`.
