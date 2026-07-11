---
name: Phase 5 Parametric EQ
description: Architecture decisions and constraints for the dsp.peq processor registered in Phase 5.
---

## Rule
dsp.peq is registered as slot 1 in the pipeline (after dsp.gain at slot 0) via
`NativeDspPipeline.initialize()`. Registration order: gain → peq. Do not change
this order without re-verifying the signal chain.

## Thread-safety protocol
Control thread: write band.pending → release-store dirty=1.
Audio thread: acquire-load dirty=1 → memcpy pending→active → relaxed-store dirty=0.
Known theoretical race (20-byte copy window) is accepted as inaudible. Any future
fix must use a triple-buffer or lock — not just tightening the atomics.

## Why coefficient computation is on the control thread
`sinf/cosf/powf` must NOT run on the ExoPlayer audio thread. `nar_biquad_compute()`
is called by `nar_peq_set_band()` (control thread only). Audio thread does zero FP
transcendentals.

## Sample rate
Caller (Dart) passes sample_rate to every `nar_peq_set_band()` call. If ≤0, C
defaults to 48000 Hz. Dart should re-apply all bands on `audioFormatStream` changes.

## How to apply
Any EQ UI feature should go through `PlaybackManager.setNativePeqBand(...)`.
Do NOT import `NativeParametricEq` directly from UI or service code.
The `NativeDspBridge.setBandGain` / `applyPreset` stubs can now delegate here.
