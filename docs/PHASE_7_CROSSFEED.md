# Phase 7 — Crossfeed & Stereo Processing Engine

Adds a frequency-dependent headphone **crossfeed** processor and a reusable
**stereo matrix framework** to the Native DSP Pipeline.

---

## Updated Signal Flow

```
ExoPlayer audio decoder
        │  float32 PCM (interleaved)
        ▼
NativeDspAudioProcessor.kt
        │
        ▼
  nar_dsp_pipeline_process_raw()
        │
        ├─ [0] dsp.gain          (Phase 4)  volume / gain
        ├─ [1] dsp.peq           (Phase 5)  parametric EQ
        ├─ [2] dsp.compressor    (Phase 6)  dynamic range compression
        ├─ [3] dsp.crossfeed     (Phase 7)  ← new: headphone crossfeed
        ├─ [4] dsp.limiter       (Phase 6)  brickwall ceiling
        └─ [5] dsp.soft_clipper  (Phase 6)  tanh overload safety net
                │
                ▼
          DefaultAudioSink → AudioTrack → DAC
```

The crossfeed sits **after the compressor** (so it works on a
dynamically-controlled signal) and **before the limiter** (so any level changes
introduced by stereo blending are still protected by the brickwall ceiling).

---

## Files Added / Modified

### New files

| File | Purpose |
|---|---|
| `native_audio_runtime/src/stereo_matrix.h` | Header-only reusable 2×2 stereo matrix framework |
| `native_audio_runtime/src/crossfeed_processor.h` | Crossfeed public API (`FFI_PLUGIN_EXPORT`) |
| `native_audio_runtime/src/crossfeed_processor.c` | Frequency-dependent crossfeed implementation |

### Modified files

| File | Change |
|---|---|
| `native_audio_runtime/hook/build.dart` | Added `crossfeed_processor.c` to CBuilder sources |
| `native_audio_runtime/src/native_audio_runtime.c` | Version `0.1.0-phase7`; `dsp.crossfeed` capability set to `1` |
| `native_audio_runtime/lib/native_audio_runtime_bindings_generated.dart` | Added `@ffi.Native` declarations for all Phase 7 exports |
| `native_audio_runtime/lib/src/dsp_pipeline_io.dart` | Added `NativeCrossfeed` class; registered in `NativeDspPipeline.initialize()` between compressor and limiter |
| `native_audio_runtime/lib/src/dsp_pipeline_unsupported.dart` | Added matching stub for `NativeCrossfeed` |
| `lib/services/audio/playback_manager.dart` | Added `setNativeCrossfeedParams`, `setNativeCrossfeedBypass`, `nativeCrossfeedBypass`, `nativeCrossfeedAvailable` |

---

## Stereo Matrix Framework (`stereo_matrix.h`)

Header-only (no `.c` file). Include from any stereo-processing module.

### NarStereoMatrix

```c
// 2×2 gain matrix: a[out_channel][in_channel]
// [L_out]   [a[0][0]  a[0][1]] [L_in]
// [R_out] = [a[1][0]  a[1][1]] [R_in]
typedef struct { float a[2][2]; } NarStereoMatrix;
```

### Factory functions

| Function | Description |
|---|---|
| `nar_stereo_matrix_identity()` | Pass-through (L→L, R→R) |
| `nar_stereo_matrix_mono()` | Full mono collapse: both channels = (L+R)/2 |
| `nar_stereo_matrix_width(w)` | Width scale: 0=mono, 1=unity, 2=double width |
| `nar_stereo_matrix_balance(pan)` | Linear pan: −1=L only, 0=center, +1=R only |
| `nar_stereo_matrix_mid_side_encode()` | M = (L+R)/2, S = (L−R)/2 |
| `nar_stereo_matrix_mid_side_decode()` | L = M+S, R = M−S |
| `nar_stereo_matrix_crossblend(amount)` | Flat crossfeed blend (no frequency dependence) |

### Composition

```c
// Apply matrix A then matrix B:
NarStereoMatrix result = nar_stereo_matrix_multiply(&B, &A);
```

### Future uses

- **Stereo Width** control: `nar_stereo_matrix_width(w)`
- **Mid/Side processing**: encode → process → decode
- **Stereo Rotation**: compose width + balance matrices
- **Balance**: `nar_stereo_matrix_balance(pan)`

---

## Crossfeed Algorithm (`crossfeed_processor.c`)

### Design

- **Frequency-dependent blending**: only low frequencies cross channels.
  High-frequency signals remain in their originating channel, preserving
  directional imaging.
- **No mono collapse**: the stereo image is preserved — the crossfeed blends
  a *filtered* version of the opposite channel, not the full signal.
- **Equal-loudness normalization**: the mix is normalized by `1/(1+amount)`
  so perceived loudness stays constant regardless of crossfeed strength.
- **HF compensation**: a high-shelf filter on the direct path partially
  restores the HF energy that would otherwise be slightly reduced by the
  normalization, giving a more neutral tonal balance.
- **Stereo width matrix**: a final post-blend width matrix allows
  fine-tuning of the perceived stereo spread independently of crossfeed amount.

### Per-frame Processing (stereo)

```
1. Cross-path lowpass filters:
   xfeed_L = lowpass_biquad_R(R_in)   — filtered R, destined for L output
   xfeed_R = lowpass_biquad_L(L_in)   — filtered L, destined for R output

2. HF compensation (high shelf on direct path):
   direct_L = hfshelf_biquad_L(L_in)
   direct_R = hfshelf_biquad_R(R_in)

3. Mix + normalize (equal-loudness):
   norm    = 1 / (1 + amount)   — pre-computed on control thread
   L_mixed = (direct_L + amount × xfeed_L) × norm
   R_mixed = (direct_R + amount × xfeed_R) × norm

4. Stereo width matrix:
   [L_out, R_out] = nar_stereo_matrix_width(width) × [L_mixed, R_mixed]
```

Mono channels (`channels == 1`) and channels beyond index 1 pass through
unchanged — the crossfeed is a stereo-only transform.

### Filter Details

**Cross-path lowpass** (2nd-order Butterworth, Q = 0.7071 = 1/√2):
- Uses the existing `nar_biquad_compute(NAR_BIQUAD_LOW_PASS, ...)` from Phase 5.
- Two independent instances (one per input channel) share the same coefficients
  but maintain separate TDF-II delay state (`s1`, `s2`).
- Cutoff default: **700 Hz** — below this frequency both ears receive similar
  levels from a speaker in a room; above this frequency the direct-path ear
  dominates.

**HF compensation shelf** (2nd-order high shelf, Q = 0.7071):
- Uses `nar_biquad_compute(NAR_BIQUAD_HIGH_SHELF, ...)`.
- Default: **+3 dB at 4000 Hz** — compensates the slight HF loss introduced
  by the normalization step when `amount > 0`.
- At `hf_comp_db = 0`, the shelf is bypassed via an identity biquad
  (b0=1, b1=b2=a1=a2=0) — zero cost.

**Compact per-channel biquad state** (`NarCfBiquadState`):
- Two floats `{s1, s2}` instead of the 8-channel arrays in `NarBiquadState`.
- Four instances stored contiguously in `NarCrossfeedState` — cache-friendly
  for the audio thread's sequential access pattern.

---

## Parameter Model

| Parameter | Range | Default | Description |
|---|---|---|---|
| `amount` | [0, 1] | 0.3 | Crossfeed blend strength. 0 = transparent; 1 = maximum. |
| `cutoff_hz` | [100, 2000] | 700 | LP cutoff frequency for the cross-channel path (Hz). |
| `hf_comp_db` | [0, 12] | 3.0 | HF shelf gain for direct-path compensation (dB). |
| `hf_comp_hz` | [1000, 16000] | 4000 | HF shelf corner frequency (Hz). |
| `width` | [0, 2] | 1.0 | Stereo width multiplier after blending. 1.0 = unity. |

All parameters are clamped to their valid ranges in `nar_crossfeed_set_params()`.

---

## Threading Model

```
Control thread                       Audio thread (every ~21 ms)
───────────────────────────────────  ─────────────────────────────────────────
PlaybackManager.setNativeCrossfeedParams()
  └─ NativeCrossfeed.setParams()     _xf_process():
       └─ nar_crossfeed_set_params()   1. acquire-load dirty
            ├─ nar_biquad_compute(LP)  2. if dirty: active=pending, clear dirty
            ├─ nar_biquad_compute(HF)  3. per-frame:
            ├─ nar_stereo_matrix_width    a. LP filter L and R cross paths
            ├─ _xf.pending = params      b. HF shelf L and R direct paths
            └─ store dirty=1 [REL]       c. mix + normalize
                                         d. apply stereo width matrix
```

**Audio thread guarantees:**
- No locks (lock-free atomics only)
- No heap allocation
- Zero transcendentals after dirty-flag swap (all biquad coefficients
  pre-computed on the control thread; audio thread runs only
  `y = b0·x + s1` — 5 multiplies + 4 adds per biquad per sample)
- Biquad state preserved across parameter updates: the IIR delay
  variables (`s1`, `s2`) are NOT reset on a param change, so transitions
  produce at most a brief imperceptible transient rather than an audible click

**On seek / track change** (`_xf_reset()`): all four biquad states are
cleared with `memset(0)` so history from the previous track does not bleed
into the new one.

---

## Performance

| Component | Cost per 1024-frame stereo buffer (48 kHz) |
|---|---|
| 4 × biquad TDF-II | 4 × 1024 × (5 mul + 4 add) ≈ **~8 µs** |
| Mix + normalize | 1024 × (4 mul + 2 add) ≈ **~2 µs** |
| Width matrix | 1024 × (4 mul + 2 add) ≈ **~2 µs** |
| **Total Phase 7** | **~12 µs** (deadline: 21 000 µs, **0.06% CPU**) |

IIR filters: **zero algorithmic latency** (causal; output at sample N
depends only on inputs ≤ N). The pipeline total latency remains 63 frames
(from the look-ahead limiter, unchanged).

---

## Dart API Reference

```dart
// Enable with default gentle crossfeed:
PlaybackManager.setNativeCrossfeedParams(
  amount:    0.3,      // 30% crossfeed blend
  cutoffHz:  700.0,    // frequencies below 700 Hz cross channels
  hfCompDb:  3.0,      // +3 dB high-shelf for HF compensation
  hfCompHz:  4000.0,   // shelf corner at 4 kHz
  width:     1.0,      // natural stereo width
  sampleRate: 48000.0,
);
PlaybackManager.setNativeCrossfeedBypass(false);  // engage

// Strong crossfeed (classical/jazz with wide stereo):
PlaybackManager.setNativeCrossfeedParams(
  amount:   0.6,
  cutoffHz: 1000.0,
  hfCompDb: 4.0,
  width:    0.9,
  sampleRate: 48000.0,
);

// Disable:
PlaybackManager.setNativeCrossfeedBypass(true);
bool isBypassed = PlaybackManager.nativeCrossfeedBypass;  // true

// Check availability:
bool available = PlaybackManager.nativeCrossfeedAvailable;
```

---

## Remaining Work Before ReplayGain & Loudness Normalization

1. **Crossfeed UI**: a settings page / bottom sheet exposing the crossfeed
   parameters. Suggested controls: an "Amount" slider, a "Preset" selector
   (Off / Gentle / Moderate / Strong), and an expert mode for cutoff + HF comp.

2. **Preset system**: named crossfeed presets:
   - `Gentle` — amount=0.2, cutoff=700, hfComp=2.0
   - `Moderate` — amount=0.4, cutoff=700, hfComp=3.0
   - `Strong` — amount=0.6, cutoff=1000, hfComp=4.0, width=0.9
   - `BS2B-style` — amount=0.45, cutoff=700, hfComp=9.5 dB (Bauer original)

3. **Width control**: expose `width` independently as a "Stereo Width" slider
   in the UI — useful even without crossfeed (width=0.5 for overly-wide mixes,
   width=1.5 for wide headphone experience).

4. **Sample-rate tracking**: when ExoPlayer reports a sample rate change
   between tracks (44.1 kHz ↔ 48 kHz), re-call `setNativeCrossfeedParams`
   with the updated rate so LP and HF coefficients are recomputed correctly.

5. **ReplayGain** (Phase 8): integrate `ReplayGainService` Dart output into
   `dsp.gain` by calling `setNativeGainDb()` with the track/album gain.
   No new C code needed.
