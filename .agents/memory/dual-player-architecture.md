---
name: Dual-Player Architecture
description: True dual-player crossfade + gapless preload architecture. Key design decisions and gotchas for maintaining the audio engine.
---

## Architecture

Two independent `PlayerSlot` instances (A and B), each with their own `AudioPlayer` + `AndroidEqualizer` + `AndroidLoudnessEnhancer` DSP pipeline.

### Slot roles
- `_activeSlot = 0`: Slot A is audible, Slot B is standby
- `AudioEngine.handoff()` swaps roles (0 ↔ 1)
- `AudioEngine.activePlayer` / `standbyPlayer` always return the current pair

### Crossfade (CrossfadeController)
- 20ms timer monitors `activePlayer.position` vs `duration`
- When `remaining ≤ crossfadeDuration`:
  1. Load next track on standby at vol=0, start playing
  2. Fade: `activeSlot.setVolume(easeOut(ratio))`, `standbySlot.setVolume(easeIn(1-ratio))`
  3. On completion: `handoff()` → stop old active → call `_onHandoffComplete(newIndex)`
- Callbacks avoid circular import: `CrossfadeController` ← registered by `AudioService`

### Gapless preload (AudioService)
- Position stream → when `remaining ≤ crossfadeDuration + 12s`: `_preloadNext()`
- `_preloadNext()` calls `standbyPlayer.setAudioSource()` but NOT `.play()` (buffered silent)
- Track completes → if `_preloadedIdx == nextIdx`: instant `_gaplessSwap()`, else `_loadAndPlay()`

### Effects after handoff
- `AudioEffectsService.reapplyToActivePlayer()` called by `AudioService` after every handoff
- Re-applies pitch + speed (player-level) and calls `AudioEngine.restoreEqBandsOnSlot()`
- `LoudnessEnhancer` + `AndroidEqualizer` are part of each slot's DSP pipeline → persist across handoffs automatically

### Native effects (Android)
- `effectsBySession: HashMap<Int, SessionEffects>` in `MainActivity.kt`
- `attachEffects(sessionId)` creates Virtualizer + BassBoost + PresetReverb per session
- `setBassBoost / setReverb / setSpatialEnabled` apply to ALL sessions in the map
- Both players get identical effect settings

## Loudness (LUFS)
- `LoudnessAnalyzer.analyze(path)`: cache → Android MediaCodec K-weighted LUFS → WAV Dart → null
- Cache key: `"$filePath:$lastModifiedMs"` (invalidated when file changes), max 1000 entries in SharedPrefs
- Target: −14 LUFS, peak ceiling: −1 dBFS
- `recommendedGainMb` → `LoudnessEnhancer.setTargetGain()` on Android; `recommendedGainLinear` → `player.setVolume()` on non-Android
- Per-track gain applied to EACH slot individually (active and standby may differ)

## AudioService queue management
- NO `ConcatenatingAudioSource` — fully manual queue
- `_playlist`, `_curIndex`, `_loopMode`, `_shuffled`, `_shuffleOrd`
- `_shuffleOrd` = permuted int list; always starts with `_curIndex`
- Subscriptions: `_playerSubs` (per-player, re-created on handoff), `_speedListener` (VoidCallback on ValueNotifier)

**Why:** ConcatenatingAudioSource can't do true dual-player crossfade since both players need to be independent.

## Breaking changes from old architecture
- `AudioEngine.player` still works (alias for `activePlayer`)  
- `AudioEngine.equalizer` → active slot's EQ
- No more `player.loopModeStream` / `shuffleModeEnabledStream` / `currentIndexStream` — all state via `AudioService.playbackState ValueNotifier`
- `AudioService.cycleLoopMode()` / `toggleShuffle()` update state directly (not via just_audio)
