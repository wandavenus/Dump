---
name: EQ slider silent no-op when system Equalizer fails to attach
description: Why "slider moves, dB updates, but no audible change" can happen for the Band EQ on real devices (esp. MIUI), and the fix applied in AudioEffectsManager.kt.
---

## Symptom
On a real Android device (confirmed on Xiaomi/MIUI 12), the Band EQ master switch is ON, sliders move and the dB label updates correctly and persists — but there is zero audible effect on playback. No crash, no visible error anywhere.

## Root cause
`AudioEffectsService._writeEqBand()` routes gain either to the native 32-band PEQ (`dsp.peq`, verified correct end-to-end) or, when that's unavailable, to Android's system `Equalizer` effect via `AudioEffectsManager.kt`. Two stacked silent-failure points in the fallback path made this invisible:
1. `attachEffects()` wraps `Equalizer(0, sessionId)` construction in a try/catch that only logs a warning on failure — no exception propagates.
2. `setEqualizerBandGain()`/`setEqualizerEnabled()` used `equalizer?.let { ... }` — if `equalizer` was null (never attached, or attach failed), the call was a complete no-op with no log line at all.
3. Compounding bug: the retry-on-failure logic in `attachEffects()` only retried when **all** effects failed (`anyOk == false`). If `LoudnessEnhancer` attached successfully but `Equalizer` specifically threw (e.g. a transient MIUI AudioFlinger race), `anyOk` was true, retries were skipped, and `equalizer` stayed null **permanently** for that track/session.

## Fix applied
In `android/app/src/main/kotlin/dev/wndavenz/music/effects/AudioEffectsManager.kt`:
- Track `eqOk` separately from `anyOk`; only settle (`lastAttachedSessionId = sessionId`, stop retrying) once `eqOk` is true, not just "some effect attached."
- `setEqualizerBandGain`/`setEqualizerEnabled` now log a `warn` line (visible via the in-app Log Viewer / NativeLogger) whenever `equalizer` is null instead of failing completely silently.

**Why:** Silent fail-open is otherwise the correct architecture for native DSP (see native-dsp-fail-open.md) — but on the Android-effects fallback path it left users with an unfixable, undiagnosable EQ that "does nothing" and no way to tell why.

**How to apply:** Any future audio-effect (LoudnessEnhancer, BassBoost, etc.) added to this fallback path should follow the same pattern — track its own `*Ok` flag if losing it silently would matter to the user, and log on null instead of swallowing via `?.let`/`catch(_: Exception) {}`.
