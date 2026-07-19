---
name: DSP Processor Parameters
description: Full parameter ranges and state structs for all 7 C DSP processors in native_audio_runtime.
---

# DSP Processor Parameters (native_audio_runtime)

## 1. Compressor (`comp_processor.h/.c`)

**`nar_comp_set_params` params:**

| Param | Range | Unit |
|-------|-------|------|
| `threshold_db` | −96 to 0 | dBFS |
| `ratio` | 1.001 to 100 | :1 |
| `attack_ms` | 0.1 to 500 | ms |
| `release_ms` | 1 to 2000 | ms |
| `knee_db` | 0 to 24 | dB |
| `makeup_gain_db` | −24 to +24 | dB |
| `sample_rate` | — | Hz |

**`NarCompState`:** `NarCompParams` (pending/active), dirty flags, bypass, `envelope_db` (smoothed peak level per stream), `last_sample_rate`.

**Phase 1 opt:** Inner gain-multiply loop has stereo fast-path (`channels==2`) unrolled.

## 2. Limiter (`limiter_processor.h/.c`)

**`nar_limiter_set_params` params:**

| Param | Range | Unit |
|-------|-------|------|
| `threshold_db` | −30 to −0.001 | dBFS |
| `release_ms` | 1 to 1000 | ms |
| `sample_rate` | — | Hz |

**Fixed:** `NAR_LIMITER_LOOKAHEAD_FRAMES = 64` (~1.3ms @ 48kHz). Total pipeline latency = 63 frames.

**`NarLimiterState`:** `threshold_linear`, `release_ms`, `coeff_release`, `gain_linear`, `delay_write_pos`, per-channel `delay_buf[64]` (circular buffer).

**Phase 1 opt:** 3 inner loops have stereo fast-path (`del_ch==2 && channels==2`): delay buffer write, peak detection, output multiply.

## 3. Loudness Normalizer (`loudness_processor.h/.c`)

**Params:**
- Target: default **−23.0 LUFS** (clamped −36.0 to −6.0)
- Smoothing tau: **3 seconds**
- Absolute gate: **−70 LUFS**
- 3s attack/release tau; asymmetric attack/release; relative gate enabled

**IIR Filter (ITU-R BS.1770-4 K-weighting, 2-stage):**
- Stage 1 Pre-filter: f0 = 1681.97 Hz, G = 3.99 dB, Q = 0.707
- Stage 2 RLB high-pass: f0 = 38.13 Hz, Q = 0.500
- Coefficients derived at live sample rate via tan()-based pre-warping

**System LE (LoudnessEnhancer) disabled when native loudness norm is on.**

## 4. Crossfeed (`crossfeed_processor.h/.c`)

**`nar_crossfeed_set_params` params:**

| Param | Range | Unit | Purpose |
|-------|-------|------|---------|
| `cutoff_hz` | 100–2000 | Hz | Lowpass for cross-channel path |
| `hf_comp_hz` | 1000–16000 | Hz | High-shelf corner for direct path |
| `amount` | 0–1 | — | Blend amount |
| `hf_comp_db` | 0–12 | dB | High-freq compensation |
| `width` | 0–2 | — | Stereo width multiplier |

Frequency-dependent; zero latency; stereo_matrix.h framework.

**Note:** `nar_stereo_matrix_apply` is `static inline` → compiler `-O3` auto-vectorizes. No manual NEON needed.

## 5. ReplayGain (`replaygain_processor.h/.c`)

**Pipeline slot 1.** Gain applied as scalar multiply; effective linear gain pre-computed on control thread.

**`nar_replaygain_set_gain` params:**

| Param | Range | Unit |
|-------|-------|------|
| `gain_db` | −24 to +24 | dB |
| `peak_linear` | — | linear | Clipping protection cap: `gain * peak ≤ 1.0` |

Pre-amp support via `gain_db`. NaN/Inf sanitization applied.

## 6. Biquad Filter (`biquad_filter.h`)

**`NarBiquadCoeffs` fields:**
```c
float b0, b1, b2;   // feed-forward coefficients
float a1, a2;       // feed-back coefficients (a0 divided out)
// positive sign convention: a1, a2 subtracted in TDF-II recurrence
```

**`NarBiquadState`:** per-channel TDF-II delay elements.

Used by: crossfeed (internal LP/shelf), loudness K-weighting.

## 7. Soft Clipper (`soft_clipper_processor.h/.c`)

- Algorithm: `tanhf`-based
- **No NEON optimization** — only meaningful opt is Padé approximation which changes clipping curve (audio quality violation)
- Default: bypass off (active) → Dart must force-bypass until user opts in

## 8. Gain (`gain_processor.h/.c`)

- `nar_gain_set_db(db)` — simple dB → linear scalar
- NEON kernel: `nar_gain_apply_neon` (16 samples/iter, `neon_kernels.S`)

## Default Bypass State
All processors (compressor, limiter, soft_clipper, crossfeed): native default `bypass=0` (ACTIVE).
Dart MUST force-bypass each on startup until user explicitly enables them.
