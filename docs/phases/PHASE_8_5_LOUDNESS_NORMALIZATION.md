# Phase 8.5 — Loudness Normalization Engine

## Objective

Real-time perceptual loudness normalization during playback.
**Separate from ReplayGain** — operates on the measured signal, not metadata.

| Feature | ReplayGain (slot 1) | Loudness Norm (slot 2) |
|---------|---------------------|------------------------|
| Source | File metadata tags | Real-time measurement |
| Standard | REPLAYGAIN_TRACK/ALBUM_GAIN | EBU R128 / ITU-R BS.1770-4 |
| Timing | Instant (pre-computed) | ~85 ms measurement window |
| Purpose | Song-to-song level matching | Gentle playback normalization |

---

## Architecture

```
Media3 (ExoPlayer)
  ↓
NativeDspAudioProcessor  (JNI — float PCM in-place)
  ↓  slot 0 — dsp.gain          (manual volume trim)
  ↓  slot 1 — dsp.replaygain    (Phase 8 — metadata gain)
  ↓  slot 2 — dsp.loudness      (Phase 8.5 — this processor)
  ↓  slot 3 — dsp.peq           (Parametric EQ)
  ↓  slot 4 — dsp.compressor    (Soft-knee compressor)
  ↓  slot 5 — dsp.crossfeed     (Headphone crossfeed)
  ↓  slot 6 — dsp.limiter       (Look-ahead brickwall)
  ↓  slot 7 — dsp.soft_clipper  (Tanh waveshaper)
  ↓
StereoWideningAudioProcessor
  ↓
Audio Output
```

---

## 1. K-Weighting (EBU R128 / ITU-R BS.1770-4)

Two biquad stages reusing `biquad_filter.h`:

| Stage | Type | f₀ (Hz) | G (dB) | Q |
|-------|------|---------|--------|---|
| Stage 1: Pre-filter | High shelf | 1681.97 | +3.9998 | 0.7072 |
| Stage 2: RLB filter | High pass | 38.135 | — | 0.5003 |

Coefficients are computed at init (default 48 kHz) and recomputed on sample-rate change via `nar_loudness_set_sample_rate()`.

---

## 2. Loudness Measurement

**IIR power integration** (no circular buffer — zero heap allocation):

```
For each frame:
  x_kw = K-weighted sample (both stages)
  power_acc += x_kw²   (per channel, then averaged)
  frame_count++

Every UPDATE_FRAMES (4096 frames ≈ 85 ms at 48 kHz):
  mean_sq = power_acc / frame_count
  LUFS = -0.691 + 10 × log₁₀(mean_sq + ε)
  → store in _measured_lufs_bits (atomic)
```

**Absolute gate** (EBU R128): gain target not updated when `LUFS < −70 LUFS`. This prevents gain chasing on silence/very quiet passages.

---

## 3. Gain Controller

```
If measured LUFS > -70 LUFS (above gate):
  gain_dB = target_LUFS - measured_LUFS
  gain_dB = clamp(gain_dB, MIN_GAIN_DB=-12, MAX_GAIN_DB=+6)
  gain_target_linear = 10^(gain_dB / 20)
```

**Limits:**
- Max boost: +6 dB (prevents over-amplifying very quiet tracks)
- Max cut: −12 dB (prevents excessive attenuation of loud tracks)

---

## 4. Gain Smoothing

First-order IIR per frame (intentionally slow — NOT a compressor):

```
α = 1 - exp(-1 / (sample_rate × τ))    τ = 3 seconds

Per frame:
  gain_smooth += α × (gain_target - gain_smooth)
  sample *= gain_smooth
```

At 48 kHz:  
- α ≈ 6.94 × 10⁻⁶  
- 63 % of target reached in ~3 s  
- 95 % of target reached in ~9 s  

**No pumping:** the 3 s time constant means the gain changes imperceptibly slowly — well below the threshold of audible pumping (~100 ms attacks).

---

## 5. Interaction with ReplayGain

```
Input audio
  → ReplayGain gain applied (slot 1, metadata-based, fast)
  → Loudness Norm applied  (slot 2, measured, slow)
  → PEQ, Compressor, etc.
```

- ReplayGain provides a coarse level offset (per-song).
- Loudness Norm provides fine real-time adjustment on top.
- If ReplayGain is disabled, Loudness Norm still functions correctly.
- If both are enabled, they complement without conflict (separate gain stages).

---

## 6. PlaybackManager Public API

```dart
// Enable / disable
PlaybackManager.setNativeLoudnessNormBypass(bool bypass);
PlaybackManager.nativeLoudnessNormBypassed;     // bool getter
PlaybackManager.nativeLoudnessNormAvailable;    // bool getter

// Target loudness
PlaybackManager.setNativeLoudnessNormTargetLufs(double lufs);  // [-36, -6]

// Status (for UI display)
PlaybackManager.nativeLoudnessMeasuredLufs;    // double getter
PlaybackManager.nativeLoudnessAppliedGainDb;   // double getter

// Track change
PlaybackManager.resetNativeLoudnessNorm();     // clears measurement + gain
```

---

## 7. Thread Safety

| Thread | Role |
|--------|------|
| Audio (ExoPlayer) | K-weighting → power integration → log10 every 4096 frames → smooth gain → multiply samples. No locks, no heap, no blocking. |
| Control (Dart) | Writes `target_lufs_bits`, `bypass`, `enabled`. Reads `measured_lufs_bits`, `applied_gain_db_bits`. Uses `set_sample_rate` with transient bypass. |

All cross-thread state uses `_Atomic int32_t` with IEEE 754 bit-pattern trick (same pattern as `gain_processor.c`, `replaygain_processor.c`).

---

## 8. Performance (Snapdragon 730 target device)

| Operation | Cost | Frequency |
|-----------|------|-----------|
| K-weighting (2 biquads × 2 ch) | ~20 FP ops/frame | Per frame (48 kHz) |
| Power accumulation | ~4 FP ops/frame | Per frame |
| Gain smoothing + multiply | ~4 FP ops/frame | Per frame |
| LUFS compute (log10f + powf) | ~2 transcendentals | Every 4096 frames (~12×/s) |
| Atomic reads (target_lufs, bypass) | 2 loads | Per buffer call |

Total per-frame overhead is ~28 FP ops — extremely lightweight.

---

## 9. Files Added

| File | Description |
|------|-------------|
| `native_audio_runtime/src/loudness_processor.c` | C implementation |
| `native_audio_runtime/src/loudness_processor.h` | C header / public API |
| `docs/PHASE_8_5_LOUDNESS_NORMALIZATION.md` | This document |

## 10. Files Modified

| File | Change |
|------|--------|
| `native_audio_runtime/lib/native_audio_runtime_bindings_generated.dart` | FFI bindings added |
| `native_audio_runtime/lib/src/dsp_pipeline_io.dart` | Registration (slot 2) + `NativeLoudnessNorm` facade; slot comments updated |
| `native_audio_runtime/lib/src/dsp_pipeline_unsupported.dart` | `NativeLoudnessNorm` web stub |
| `lib/services/audio/playback_manager.dart` | `setNativeLoudnessNorm*` methods |
| `lib/services/audio/audio_effects_service/service.dart` | `loudnessNormEnabled`, `loudnessNormTarget` VNs + setters |
| `lib/services/audio_service/service.dart` | Apply loudness norm settings; reset on track change |
| `lib/pages/settings_page/audio.dart` | Loudness Normalization section in Audio settings |

---

## 11. Remaining Work Before FFmpeg Integration

1. **Sample-rate tracking** — ExoPlayer should report sample-rate changes via an EventChannel event; `nar_loudness_set_sample_rate()` (and the crossfeed re-parametrize) should be called from the track metadata event handler.

2. **Multi-channel weights** — ITU-R BS.1770 assigns 1.5× weight to surround channels (Ls, Rs). Current implementation uses equal weights (1.0×) — acceptable for stereo. If multichannel support is added, weights should be updated.

3. **Loudness visualization** — a real-time LUFS meter widget reading `nativeLoudnessMeasuredLufs` via a periodic timer for the debug/settings UI.

4. **Adaptive time constants** — future improvement: shorter attack (e.g., 0.5 s) for large gain deltas (> 3 dB) and longer release (5 s) for small ones, preventing both slowness-at-start and audible pumping mid-track.

5. **FFmpeg integration (Phase 9)** — offline LUFS scanning per track to pre-seed the loudness target, reducing the initial 3–9 s warm-up period.
