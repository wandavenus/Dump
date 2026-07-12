---
name: Phase 7 Crossfeed
description: Frequency-dependent headphone crossfeed — what changed in pipeline, stereo matrix framework, and tests
---

# Phase 7 Crossfeed

## Pipeline now has 6 slots (in order)
- [0] dsp.gain (Phase 4)
- [1] dsp.peq (Phase 5)
- [2] dsp.compressor (Phase 6)
- [3] dsp.crossfeed (Phase 7) ← between compressor and limiter
- [4] dsp.limiter (Phase 6)
- [5] dsp.soft_clipper (Phase 6)

**Total pipeline latency: still 63 frames** (IIR crossfeed is zero-latency; only limiter look-ahead counts).

## New files

- `stereo_matrix.h` — header-only 2×2 matrix framework; reusable by future processors (width, M/S, balance, rotation, crossblend)
- `crossfeed_processor.h/.c` — frequency-dependent BS2B-inspired crossfeed

## Algorithm (crossfeed_processor.c)

Per stereo frame:
1. LP biquad (Butterworth Q=0.7071) on each cross path: `xfeed_L = LP(R)`, `xfeed_R = LP(L)`
2. High-shelf on direct path (HF compensation): `direct_L = HF(L)`, `direct_R = HF(R)`
3. Mix + normalize: `norm = 1/(1+amount)`, L_mixed/R_mixed
4. Stereo width matrix: `nar_stereo_matrix_width(width)` applied to mixed pair

Mono channels (< 2 ch) and channels > 1 pass through unchanged.

## Thread safety pattern

Same double-buffer + acquire/release dirty flag as compressor. All biquad coefficients (`NarBiquadCoeffs` × 2 types) and width matrix (`NarStereoMatrix`) are pre-computed in `_build_params()` on the control thread. Audio thread only does a 92-byte struct copy on dirty.

**Biquad state is NOT reset on param update** (would cause click). State decays within milliseconds under new coefficients. Reset only on seek/track change (`_xf_reset()`).

## NarCfBiquadState

Uses compact `{float s1, s2}` instead of the 8-channel `NarBiquadState` arrays. 4 instances stored contiguously — cache-friendly.

## hf_comp_db = 0 optimization

When `hf_comp_db ≤ 0.0001`, the HF shelf is replaced with an identity biquad `{b0=1, b1=b2=a1=a2=0}` — zero computation cost, no filter artifacts.

## Test isolation pattern for 6-slot pipeline

When testing a single processor, disable all 5 others explicitly:
```dart
NativeDspPipeline.instance.setProcessorEnabled('dsp.gain', enabled: false);
NativeDspPipeline.instance.setProcessorEnabled('dsp.peq', enabled: false);
NativeDspPipeline.instance.setProcessorEnabled('dsp.compressor', enabled: false);
NativeDspPipeline.instance.setProcessorEnabled('dsp.crossfeed', enabled: false);
NativeDspPipeline.instance.setProcessorEnabled('dsp.limiter', enabled: false);
NativeDspPipeline.instance.setProcessorEnabled('dsp.soft_clipper', enabled: false);
```

## Documentation

`docs/PHASE_7_CROSSFEED.md` — algorithm, stereo matrix framework, signal flow, parameter model, threading, performance table, Dart API reference, remaining work.
