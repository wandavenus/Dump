---
name: Bit-Perfect Mode dedicated player
description: Third ExoPlayer instance used only when Bit-Perfect Mode is on; how it's wired into the existing dual-player crossfade architecture.
---

Bit-Perfect Mode (existing Dart toggle in `AudioEffectsService.setBitPerfectMode`) now
also switches native playback onto a **third** ExoPlayer instance — `bitPerfectPlayer`
in `Media3PlaybackService.kt` — with zero custom `AudioProcessor`s (no NativeDsp, no
StereoWidening) and `setEnableAudioFloatOutput(false)`. It never runs concurrently with
`primaryPlayer`/`secondaryPlayer`: crossfade is cancelled and the standby player released
before switching to it, and `AudioEffectsManager.releaseEffects()` is called so no
AudioEffect stays attached to its session.

**Why:** true bit-perfect requires a processing-free player — Media3 disqualifies
exclusive/offload paths the instant any AudioProcessor/AudioEffect is attached, even if
neutral (see `docs/bit_perfect_playback_report.md`).

**How to apply:** `activePlayer` is a plain var read by closures everywhere
(QueueManager/CrossfadeController/PreloadManager/etc via `getPlayer = { activePlayer }`),
so switching it plus `activePlayerProxy.switchTo(newPlayer)` plus
`queueManager.setQueue(queue, activeQueueIndex, positionMs)` is enough to move playback
onto/off any player — this is the same pattern already used for crossfade promotion.
Entry point: `TransportCommands` dispatch `"setBitPerfectMode"` → Dart
`Media3PlaybackBridge.setBitPerfectMode` / `PlaybackManager.setBitPerfectMode`, called
from `AudioEffectsService.setBitPerfectMode()` (native switch-off happens *before*
`_restoreFromBitPerfectSnapshot()` so restored effect/crossfade settings apply to the
correct post-switch session; native switch-on happens *after* `_forceBypassEverything()`).
No new UI — rides entirely on the existing toggle. Not compile-verified here (no Android
Gradle toolchain in this sandbox) — only `flutter analyze` on the Dart side; real
verification needs the physical device build.

**Gotcha found on-device (2026-07-13):** the shared per-player `Player.Listener`'s
`onAudioSessionIdChanged` unconditionally called `effectsManager.attachEffects(sessionId)`
for whichever player fired it. Since `attachPlayerListener()` is reused for the bit-perfect
player too, its first session-ID assignment re-attached EQ/LoudnessEnhancer/BassBoost/
Virtualizer right onto the "clean" session, silently defeating the whole point. Fixed by
guarding that call with `if (p !== bitPerfectPlayer)`. Lesson: any *generic* per-player
listener/callback shared across all ExoPlayer instances needs an explicit bit-perfect-player
exclusion check — don't assume a player-agnostic callback is safe just because it's already
used elsewhere.

**Hardware offload opt-in (1.5.56, Media3 1.11.1):** the Bit-Perfect player is the only
pipeline allowed to request audio offload. `createBitPerfectPlayer()` builds a
`TrackSelectionParameters.AudioOffloadPreferences` with
`AUDIO_OFFLOAD_MODE_ENABLED` (not `REQUIRED`, so unsupported formats fall back to PCM)
and applies it through `DefaultTrackSelector.buildUponParameters()
.setAudioOffloadPreferences(...)`. Do not copy this to `createConfiguredPlayer()`: the
dual-player pipeline always has crossfade/standby overlap, software effects, and custom
AudioProcessors that make offload ineligible. Media3 1.11.1 has no
`DefaultRenderersFactory.setEnableAudioOffload`; track selection is the supported switch.
Caveat: EXTENSION_RENDERER_MODE_PREFER still routes ALAC/Vorbis etc. through the
FFmpeg renderer, which never supports offload; offload only applies to formats handled by
MediaCodecAudioRenderer and supported by the device's DSP. Opus is handled by MediaCodec
since 1.5.57 (FFmpeg no longer builds an Opus decoder), so it can offload when the DSP
supports it.
Gapless note: `isGaplessSupportRequired` is left at its default `false`, matching
`AUDIO_OFFLOAD_MODE_ENABLED` semantics (offload may still be selected when the DSP lacks
gapless offload). If hardware testing shows audible gaps at track transitions, set it to
`true` so Media3 falls back to PCM for formats without gapless offload.
