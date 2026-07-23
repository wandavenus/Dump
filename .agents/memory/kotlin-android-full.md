---
name: Kotlin Android Full File List
description: Complete .kt file inventory under android/app/src/main/kotlin/ with class and role.
---

# Kotlin Android — Full File List

Base package: `dev.wndavenz.music`

## Root Level

| File | Class | Role |
|------|-------|------|
| `MainActivity.kt` | `MainActivity` | Main entry; 5 MethodChannels + multiple EventChannels for MediaStore, audio effects, playback |
| `Media3PlaybackService.kt` | `Media3PlaybackService` | Core playback service; dual-ExoPlayer + Bit-Perfect player; session lifecycle; Handler sleep timer; single `startForeground()` guard |
| `ActivePlayerProxy.kt` | `ActivePlayerProxy` | `ForwardingPlayer` wrapper; migrates MediaSession/AVRCP listeners between primary ↔ standby during crossfade |
| `AudioEngineManager.kt` | `AudioEngineManager` | Static facade → Media3PlaybackBridge; `registerPostSwitchCallback()` = no-op stub |
| `ArtworkCacheManager.kt` | `ArtworkCacheManager` | Track artwork cache; filesDir/supportDir (not cacheDir); `_diskCachedIds` pre-scan |
| `FallbackBitmapLoader.kt` | `FallbackBitmapLoader` | Default imagery when artwork unavailable |
| `ExoMetadataReader.kt` | `ExoMetadataReader` | ExoPlayer MetadataRetriever tag reading |
| `MetadataCacheDb.kt` | `MetadataCacheDb` | SQLite metadata cache keyed by mtime |

## effects/

| File | Class | Role |
|------|-------|------|
| `effects/NativeDspAudioProcessor.kt` | `NativeDspAudioProcessor` | ExoPlayer AudioProcessor → JNI → native_audio_runtime DSP pipeline |
| `effects/AudioEffectsManager.kt` | `AudioEffectsManager` | Coordinates all effects; syncs Dart params to native |
| `effects/StretchManager.kt` | `StretchManager` | Signalsmith Stretch STFT time-stretch/pitch-shift |
| `effects/StretchAwareAudioProcessorChain.kt` | `StretchAwareAudioProcessorChain` | Overrides `getMediaDuration`; frame-ratio counters fix position drift; real-device verified |

## replaygain/

| File | Class | Role |
|------|-------|------|
| `replaygain/ReplayGainScanner.kt` | `ReplayGainScanner` | JNI → libebur128 offline EBU R128 analysis |
| `replaygain/ReplayGainTagger.kt` | `ReplayGainTagger` | TagLib tag writes; temp-file + atomic-rename; M4A write unsupported |

## MethodChannels & EventChannels (defined in MainActivity.kt)

| Channel | Direction | Purpose |
|---------|-----------|---------|
| playback control channel | Dart→Native | play, pause, seek, setQueue, skip, insertNext, appendToQueue, removeFromQueue, reorderQueue |
| audio effects channel | Dart→Native | DSP params: EQ bands, compressor, limiter, crossfeed, loudness, ReplayGain mode |
| MediaStore channel | Native→Dart | getSongs() — scans device audio files |
| queue state EventChannel | Native→Dart | queue mutations confirmation stream |
| sleep timer EventChannel | Native→Dart | countdown tick stream |
| playback state EventChannel | Native→Dart | position, playing, buffering, track change |

## Key Architecture Rules
- **3 ExoPlayer instances**: playerA (normal), playerB (normal crossfade), playerBitPerfect (zero AudioProcessors)
- **Crossfade**: runs in `Media3PlaybackService` Handler tick; promotion after fade-in complete
- **Bit-Perfect**: switches via `activePlayer` var reassignment + `activePlayerProxy.switchTo()`
- **Queue persistence**: SharedPrefs `media3_queue_prefs`; save after every mutation; restore on `onCreate()` without autoplay
- **Notification MIUI12**: `startForeground()` once only (isForeground guard); subsequent updates via `NotificationManager.notify()`
- **Service startup**: `needsService` allowlist only includes methods that guarantee reaching `ensureMediaForeground()`
- **Crossfade repeat-all fix**: remove prefix items + set `repeatMode=OFF` AFTER `setActivePlayer` to avoid queue[0] 1s artifact
- **Audio output modes**: Auto/AAudio, OpenSL ES, Hi-Res (5-method enableHiRes: AudioManager.setParameters various keys, MIUI broadcast, ContentResolver, Sony/Qualcomm)
