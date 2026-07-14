---
name: Spatial Audio / Virtualizer removed
description: Android system Virtualizer effect and its "Spatial Audio" UI were deliberately removed at user request — do not re-add or confuse with StereoWidthManager.
---

The "Spatial Audio" feature (backed by `android.media.audiofx.Virtualizer`) was
fully removed from the app (Dart UI/service layer + `AudioEffectsManager.kt` +
`TransportCommands.kt` + `MainActivity.kt` method-channel handlers) at the
user's request on 2026-07-14. `flutter analyze` was clean after removal.

**Why:** user said they rarely use it and asked for it to be deleted.

**How to apply:**
- Do not re-add a "Spatial Audio" / Virtualizer toggle unless the user asks again.
- This is unrelated to **stereo widening**, which is a separate, still-active
  software DSP feature (`StereoWidthManager.kt` /
  `StereoWideningAudioProcessor.kt`, a custom Media3 AudioProcessor matrix,
  not a system `AudioEffect`). Never delete or touch stereo widening when
  asked to remove "spatial audio" / "virtualizer" — they are easy to confuse
  by name alone.
- `AudioEffectsManager.getEffectSupport()`/`effectSupportMap()` now only
  reports `bassBoostSupported`; `virtualizerSupported` no longer exists.
