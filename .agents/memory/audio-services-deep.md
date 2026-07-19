---
name: Audio Services Deep Map
description: Detail on PlaybackManager, Media3PlaybackBridge, AudioEffectsService, NativeModuleRegistry, and channel contracts.
---

# Audio Services — Deep Map

## PlaybackManager (`lib/services/audio/playback_manager.dart`)

Root coordinator for all playback. Owns:
- `NativeModuleRegistry` — registers `FfmpegDecoderBridge.instance` + `NativeDspBridge.instance`
- `AudioService` — high-level playback commands
- `Media3PlaybackBridge` — Android-specific MethodChannel adapter

**Key public methods** (sends via MethodChannel):
- `play()`, `pause()`, `seek(ms)`, `skipNext()`, `skipPrev()`
- `setQueue(songs, index)` — replaces native queue
- `insertNext(song)`, `appendToQueue(song)`, `removeFromQueue(index)`, `reorderQueue(from, to)`
- DSP forwarding: `setEqBand(band, gain)`, `setCompressorParams(...)`, `setLimiterThreshold(...)`, `setCrossfeedParams(...)`, `setReplayGainMode(mode)`, `setLoudnessNorm(enabled)`
- `enableBitPerfect(bool)` — switches to/from zero-processor ExoPlayer

**Communication pattern:**
- Commands → MethodChannel (fire-and-forget or await result)
- State ← EventChannel streams (queue, position, sleep timer)

## Media3PlaybackBridge (`lib/services/audio/media3/media3_playback_bridge.dart`)

Android-specific MethodChannel/EventChannel wiring:

| Channel name | Type | Purpose |
|---|---|---|
| `dev.wndavenz.music/playback` | MethodChannel | All playback commands |
| `dev.wndavenz.music/effects` | MethodChannel | DSP parameter sync |
| `dev.wndavenz.music/mediastore` | MethodChannel | `getSongs()` — MediaStore scan |
| `dev.wndavenz.music/queue_events` | EventChannel | Queue mutation confirmations |
| `dev.wndavenz.music/sleep_timer` | EventChannel | Sleep timer countdown ticks |
| `dev.wndavenz.music/playback_state` | EventChannel | Position, playing, buffering, track change |

`syncFromNative()` called from `main.dart` + `app_state.dart` on startup to pull initial state.

## AudioEffectsService (`lib/services/audio/audio_effects_service/service.dart`)

Central DSP settings controller:
- Persists all DSP state to `SharedPreferences`
- Forwards changes to native engine via `PlaybackManager`
- Manages: EQ bands, ReplayGain mode, compressor params, limiter threshold, crossfeed, loudness norm, stereo width, bit-perfect master switch
- **Bit-Perfect mode**: app-wide audio-bypass master switch; snapshot-to-prefs + force-off + UI lock pattern; lives in Settings root, NOT inside Equalizer page
- **ReplayGain/LN mutual exclusion**: ReplayGain and Loudness Normalization cannot be active simultaneously
- **System EQ**: sole Band EQ backend (native PEQ fully removed); legacy system `Equalizer` — silent attach failure handled with `eqOk` tracking + logging

## NativeModuleRegistry (`lib/services/native/native_module_registry.dart`)

Manages lifecycle of all `NativeModule` instances:
- `NativeModule` interface: `initialize()`, `dispose()`, `queryCapabilities()` → `NativeCapability`
- `NativeModuleStatus` enum: uninitialized / available / error / ...
- Registered modules:
  1. `FfmpegDecoderBridge` — FFmpeg Media3 extension via reflection + guarded optional Gradle module
  2. `NativeDspBridge` — FFI → `NativeAudioRuntime` C singleton; `moduleId = "native_dsp"`

## AudioSessionHandler (`lib/services/audio/audio_session_handler/handler.dart`)

- Configures OS-level `AudioSession` with `AudioSessionConfiguration.music()`
- Focus management and "noisy" headphone events handled natively
- Primarily sets session category

## Native Bridges (`lib/services/native/bridges/`)

| File | Class | Role |
|------|-------|------|
| `native_dsp_bridge.dart` | `NativeDspBridge` | FFI → C `NativeAudioRuntime` singleton; `initialize()` sets up FFI; `queryCapabilities()` probes runtime |
| `ffmpeg_decoder_bridge.dart` | `FfmpegDecoderBridge` | Media3 FFmpeg extension via reflection; RenderersFactory self-registers; APE/WavPack/TAK deferred |

## pubspec.yaml Key Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `http` | ^1.6.0 | HTTP for lyrics providers |
| `cached_network_image` | ^3.4.1 | Network image caching |
| `audio_session` | ^0.2.3 | OS audio session config |
| `permission_handler` | ^12.0.3 | Runtime permissions |
| `shared_preferences` | ^2.5.3 | Settings + queue persistence |
| `rxdart` | ^0.28.0 | Reactive streams |
| `path_provider` | ^2.1.5 | File system paths |
| `scrollable_positioned_list` | ^0.3.8 | Lyrics scroll |
| `palette_generator_plus` | ^1.0.0 | Artwork dominant color |
| `native_audio_runtime` | local path | C DSP engine FFI |
| `font_awesome_flutter` | ^11.0.0 | Icons |
