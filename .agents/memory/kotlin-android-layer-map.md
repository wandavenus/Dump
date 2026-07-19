---
name: Kotlin Android Layer Map
description: Every Kotlin file under android/app/src/main/kotlin/ with class, key methods, and role.
---

# Kotlin Android Layer Map

Base package: `dev.wndavenz.music`

## Core Playback

| File | Class | Key methods | Role |
|------|-------|-------------|------|
| `Media3PlaybackService.kt` | `Media3PlaybackService` | `onCreate`, `onStartCommand`, `ensureMediaForeground` | Core lifecycle: Media3/ExoPlayer + MethodChannel hub. Single startForeground() guard (isForeground). Handler-based sleep timer. |
| `ActivePlayerProxy.kt` | `ActivePlayerProxy` | `getWrappedPlayer`, `switchTo` | Manages active vs. background ExoPlayer instances during crossfade/transition |
| `AudioEngineManager.kt` | `AudioEngineManager` | static facade | Static facade → Media3PlaybackBridge; `registerPostSwitchCallback()` = no-op stub |

## Artwork

| File | Class | Role |
|------|-------|------|
| `ArtworkCacheManager.kt` | `ArtworkCacheManager` | Track artwork cache/retrieval; storage in filesDir/supportDir |
| `FallbackBitmapLoader.kt` | `FallbackBitmapLoader` | Default imagery when artwork unavailable |

## Effects

| File | Class | Role |
|------|-------|------|
| `effects/NativeDspAudioProcessor.kt` | `NativeDspAudioProcessor` | ExoPlayer AudioProcessor that calls into native_audio_runtime via JNI |
| `effects/StretchManager.kt` | `StretchManager` | Signalsmith Stretch time-stretch / pitch-shift wrapper |
| `effects/AudioEffectsManager.kt` | `AudioEffectsManager` | Coordinates all effects; syncs params from Dart |

## ReplayGain

| File | Class | Role |
|------|-------|------|
| `replaygain/ReplayGainScanner.kt` | `ReplayGainScanner` | JNI calls → libebur128 for offline EBU R128 analysis |
| `replaygain/ReplayGainTagger.kt` | `ReplayGainTagger` | TagLib tag writes; temp-file + atomic-rename crash safety; M4A unsupported |

## Metadata

| File | Class | Role |
|------|-------|------|
| `ExoMetadataReader.kt` | `ExoMetadataReader` | ExoPlayer MetadataRetriever-based tag reading |
| `MetadataCacheDb.kt` | `MetadataCacheDb` | SQLite cache keyed by mtime; scan results stored here, not to file |

## Queue / State

| File | Key details | Role |
|------|------------|------|
| `QueueManager.kt` | SharedPrefs `media3_queue_prefs`; keys: queue_json/queue_index/position_ms/repeat_mode/shuffle_enabled | Queue persistence; save after every mutation; restore on onCreate() without autoplay |

## Notification

| File | Role |
|------|------|
| `NotificationManager.kt` | Notification buttons via addAction(); buttons: PLAY_PAUSE/SKIP_NEXT/SKIP_PREV; MIUI12 fix: startForeground() once only |

## Key Architectural Rules (Kotlin side)
- **Dual-player**: 3 ExoPlayer instances (normal A, normal B, bit-perfect). Crossfade/promotion runs in Media3PlaybackService Handler tick.
- **Queue ownership**: native owns queue + shuffle (`shuffleModeEnabled`) + repeat + sleep timer; Dart = pure EventChannel consumer.
- **Service startup**: `onCreate()` never calls `startForeground()`; only `ensureMediaForeground()` callsite may do so after play/setQueue.
- **Crossfade repeat-all artifact**: After `setActivePlayer`, remove prefix items + set `repeatMode=OFF` to avoid queue[0] playing ~1s during fade.
