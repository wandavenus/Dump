---
name: Phase 8.5 Loudness Normalization Engine
description: EBU R128 real-time loudness normalization at DSP slot 2; NativeLoudnessNorm facade; pipeline slots renumbered.
---

## Rule
`dsp.loudness` sits at slot 2 (between `dsp.replaygain`=1 and `dsp.peq`=3). Inserting a new slot pushes all downstream slot numbers up by one — update DSP slot comments accordingly (peq=3, comp=4, crossfeed=5, limiter=6, soft_clipper=7).

**Why:** Phase 8.5 spec requires loudness norm to operate after ReplayGain (coarse metadata gain) but before PEQ (user tone shaping).

## Key design decisions

- **Algorithm:** IIR power integration (no circular buffer = zero heap allocation on audio thread). K-weighted via two biquad stages from `biquad_filter.h` (pre-filter: high-shelf 1681.97 Hz +3.9998 dB Q=0.7072; RLB: high-pass 38.135 Hz Q=0.5003).
- **LUFS update:** every 4096 frames (≈85 ms at 48 kHz). `log10f` / `powf` only inside this block — NOT per sample.
- **Gain smoothing:** first-order IIR α = 1−exp(−1/(sr×3s)) per frame ≈ 6.94×10⁻⁶ at 48 kHz. Very gentle — NOT a compressor.
- **Absolute gate:** no gain update when measured LUFS < −70 LUFS (prevents pumping on silence).
- **Gain clamp:** max +6 dB boost / −12 dB cut relative to measurement.
- **Sample-rate change:** transient bypass (atomic_store bypass=1 → recompute coeffs → reset → restore bypass) is safe; stale coeffs for ≤1 buffer is inaudible.
- **Thread safety:** same IEEE 754 float-bit-pattern atomic trick as gain_processor.c and replaygain_processor.c.

## Dart API
`NativeLoudnessNorm.instance` → `PlaybackManager.setNativeLoudnessNorm*` → `AudioEffectsService.{loudnessNormEnabled, loudnessNormTarget}`.
SharedPrefs keys: `lnEnabled` (bool), `lnTarget` (double, default −23.0).

## How to apply
When adding another DSP slot in the future: insert registration BETWEEN the two neighbours in `dsp_pipeline_io.dart` `initialize()` method; bump all downstream slot number comments. No changes to native_audio_runtime.dart needed (exports via dsp_pipeline_io/unsupported conditional).

## Default state
Processor starts **bypassed** (user must enable in Settings → Audio → Loudness Normalization).
`resetNativeLoudnessNorm()` is called on every track change in `AudioService._onNativeCurrentTrackChanged`.
