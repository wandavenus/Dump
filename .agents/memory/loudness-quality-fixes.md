---
name: Loudness normalization quality fixes
description: Fixes for audio quality issues in the loudness normalization pipeline — read before touching loudness_processor.c, _applyReplayGain, or setLoudnessNormEnabled.
---

## Fixes applied

### 1. Sample rate propagation to loudness_processor.c
**Rule:** `AudioService.initialize()` now subscribes to `PlaybackManager.audioFormatStream` and calls `PlaybackManager.setNativeLoudnessSampleRate(sr)` on every track change.
**Why:** `_ln_init()` hardcodes 48 kHz for the K-weighting biquad coefficients. Without this subscriber, 44.1 kHz files produce wrong LUFS measurements and wrong normalization gain.
**How to apply:** If you add another DSP processor that needs sample-rate-aware coefficients, hook into the same `audioFormatStream` subscriber in `audio_service/service.dart` (lines ~170-185).

### 2. Asymmetric attack/release in loudness_processor.c
**Rule:** Two separate alpha coefficients: `_alpha_attack` (ATTACK_TAU_SEC=0.3s) for gain reduction, `_alpha_release` (RELEASE_TAU_SEC=3.0s) for gain increase.
**Why:** Using a single 3s tau for both directions meant loud transients took 3s to attenuate — potential momentary overloads. Standard practice: fast attack, slow release.
**How to apply:** The hot loop in `_ln_process` picks `const float _alpha = (gain_target < _gain_smooth) ? _alpha_attack : _alpha_release;`. Both are recomputed in `_compute_kw_coeffs()` whenever sample rate changes.

### 3. Relative gating added to loudness_processor.c
**Rule:** Gain update is skipped when current block is more than `GATE_REL_LU` (10 LU) below the running loudness estimate.
**Why:** Without relative gate, silence/quiet intros bias the normalizer into excessive boosting. Added alongside the existing absolute gate (−70 LUFS).
**How to apply:** `rel_ok` is always true when running estimate is itself below absolute gate (startup/reset), so first block always primes the gain. No startup artifact.

### 4. ReplayGain + Loudness Norm mutual exclusion
**Rule:** In `_applyReplayGain()`, if `AudioEffectsService.loudnessNormEnabled.value` is true, bypass native ReplayGain gain and only forward the preamp offset (if non-zero).
**Why:** Both systems adjust gain independently. With both active, the EBU R128 loop re-normalizes an already ReplayGain-adjusted signal → unstable, oscillating gain.
**How to apply:** If loudness norm is re-enabled or disabled, `_onReplayGainSettingChanged` fires automatically via listener, which calls `_applyReplayGain` again and re-evaluates the coordination logic.

### 5. System LoudnessEnhancer disabled when native norm is enabled
**Rule:** `AudioEffectsService.setLoudnessNormEnabled(true)` now calls `PlaybackManager.setLoudnessEnabled(false)` + `setLoudnessTargetGain(0.0)`.
**Why:** System LoudnessEnhancer (AudioFlinger) and native EBU R128 (ExoPlayer audio processor) are in series. Both active = double gain boost + potential clipping.
**Note:** Reverse interlock (system LE → disable native norm) not implemented — would require intercepting `DeviceDsp.applyNormalize()` which is called from the settings UI. Consider adding if double-active is still possible via Settings UI path.

### 6. Batch ReplayGain library scan
**Rule:** `ReplayGainService.scanLibrary(List<LocalSong>)` scans songs sequentially via `scanReplayGain` MethodChannel. Uses existing `ReplayGainScanner.kt` (MediaCodec + EBU R128). Progress tracked via `ReplayGainService.scanProgress` (ValueNotifier<BatchScanProgress>). UI lives in `_BatchScanSection` inside Settings → Audio → Audio Normalize (collapsible area).
**Why:** Before this, users with untagged files had no way to pre-compute RG data for the whole library in one go. Only per-song on-demand scan existed.
**How to apply:** The scan skips songs already in `_cache` with non-zero gainDb. 60ms inter-song yield to avoid thermal throttling on Snapdragon 730. `cancelScan()` sets `_cancelRequested=true`; current song always finishes. Adds `dart:async show unawaited` + `ReplayGainService` + `MediaStoreService` imports to `settings_page.dart`.
