---
name: Android native effects
description: Virtualizer/BassBoost/PresetReverb diinit via MethodChannel musicplayer/audio_effects; session ID dari just_audio androidAudioSessionIdStream.
---

## Channel
`musicplayer/audio_effects` di `MainActivity.kt`

## Flow
1. just_audio emit `androidAudioSessionIdStream` → `AudioEngine._listenToSessionId()`
2. `AudioEngine._attachNativeEffects(sessionId)` → invoke `attachEffects` ke Kotlin
3. Kotlin: inisialisasi `Virtualizer(0, sessionId)`, `BassBoost(0, sessionId)`, `PresetReverb(0, sessionId)`
4. Setelah itu `setSpatialEnabled`, `setBassBoost`, `setReverb` bisa dipakai

## Penting
- `attachEffects` harus dipanggil SEBELUM set/enable effects lainnya
- Effects di-release di `MainActivity.onDestroy()`
- Strength BassBoost: 0-1000 (Short di Kotlin)
- Reverb presets: 0=NONE, 1=SMALLROOM, 2=MEDIUMROOM, 3=LARGEROOM, 4=MEDIUMHALL, 5=LARGEHALL, 6=PLATE
- Virtualizer strength diset hardcode ke 1000 saat enabled

**Why:** Tidak ada Flutter package yang wrap Virtualizer/BassBoost/PresetReverb secara lengkap. Implementasi native Kotlin lebih reliable dan zero-latency.
