---
name: Phase 8 ReplayGain Engine
description: NativeReplayGain DSP pipeline slot 1 wiring — key decisions and gotchas for Phase 8 implementation.
---

# Phase 8 ReplayGain Engine

## Key decisions

**Why:** `_applyReplayGain` was previously using `DeviceDsp.applyNormalize()` → `LoudnessEnhancer` (Android system effect). Phase 8 moves it to `NativeReplayGain` (DSP pipeline slot 1) to match the architecture spec.

**How to apply:**
- `PlaybackManager.setNativeReplayGain(gainDb, peakLinear, useClippingProtection)` is the sole caller of `NativeReplayGain.instance`.
- `AudioService._applyReplayGain()` passes raw `data.gainDb + preamp` (NOT `safeGain()`) — let the C layer handle clipping via `useClippingProtection`.
- Bypass the processor when mode=off or no metadata found; engage after gain is set.

## Duplicate enum gotcha

`playback_manager.dart` had a duplicate `ReplayGainMode` enum (`disabled/track/album/auto`) that conflicted with `models/replay_gain_mode.dart` (`off/auto/track/album`). The one in `playback_manager.dart` was removed — only the models one survives.

**Why it matters:** `audio_effects_service.dart` imports both files; having two `ReplayGainMode` enums causes an `ambiguous_import` error across the whole compilation unit.

## New state in AudioEffectsService

- `clippingProtection` ValueNotifier (default: `true`, key: `rgClipProtect`)
- `setClippingProtection(bool)` persists to SharedPrefs and triggers `_onReplayGainSettingChanged`
- All three listeners in AudioService: `replayGainMode`, `replayGainPreamp`, `clippingProtection`

## Pipeline slot order (Phase 8 complete)

slot 0: dsp.gain → slot 1: dsp.replaygain → slot 2: dsp.peq → slot 3: dsp.compressor → slot 4: dsp.crossfeed → slot 5: dsp.limiter → slot 6: dsp.soft_clipper
