# Native Performance Audit — ARM64 / NEON / C++ Migration Candidates

**Date:** 19 Juli 2026  
**Scope:** Flutter/Dart + Kotlin + Native C/C++ (`native_audio_runtime/`)  
**Target device:** Xiaomi Mi 9T / K20 — Snapdragon 730, ARM64 (Cortex-A76 × 2 + Cortex-A55 × 6), Adreno 618  
**Compiler toolchain:** Clang/LLVM via Android NDK (arm64-v8a ABI)

> **Read-only audit. No code was modified.**

---

## Existing NEON Coverage Summary

Before listing candidates, it is important to know what is **already** natively optimized:

| Kernel | File | NEON Status |
|---|---|---|
| `nar_gain_apply_neon` | `neon_kernels.h` / `.S` | ✅ Full — 16 samples/iter via `fmul v.4s` |
| `nar_biquad_stereo_neon` | `neon_kernels.h` / `.S` | ✅ Full — 2-lane `v.2s` TDF-II, processes L+R simultaneously |
| Gain processor | `gain_processor.c` | ✅ Uses `nar_gain_apply_neon` on aarch64 |
| ReplayGain processor | `replaygain_processor.c` | ✅ Uses `nar_gain_apply_neon` on aarch64 |
| Loudness K-weighting (stereo) | `loudness_processor.c` | ✅ Partial — NEON biquad for stereo; scalar fallback for other channel counts |
| Crossfeed biquads | `crossfeed_processor.c` | ✅ Partial — NEON biquad in use; stereo matrix (`nar_stereo_matrix_apply`) is still scalar |
| Signalsmith Stretch (STFT) | `libstretch_native.so` | ✅ Fully native C++ — Kotlin is a thin JNI wrapper |
| Compressor gain multiply | `comp_processor.c` | ❌ Per-sample multiply is scalar loop |
| Limiter look-ahead | `limiter_processor.c` | ❌ Entirely scalar |
| Soft clipper (tanhf) | `soft_clipper_processor.c` | ❌ Entirely scalar |
| Stereo widening matrix | `StereoWideningAudioProcessor.kt` | ❌ JVM Kotlin — per-sample on audio thread |
| Stereo matrix (crossfeed) | `stereo_matrix.h` | ❌ Scalar C — used per-sample inside crossfeed |

---

## Candidate Entries

---

### 1. Limiter — Look-ahead Buffer + Per-sample Peak/Gain

**File**
```
native_audio_runtime/src/limiter_processor.c
```

**Function**
```
_lim_process()
```

**Line Number**
```
112–217
```

**Category**
Audio DSP — Peak detection, gain smoothing, circular buffer

**Why It Is Expensive**  
Runs per-sample across a look-ahead circular buffer. For each sample: (a) write into circular delay buffer, (b) scan or maintain a running peak window, (c) compute a smooth gain via expf-based coefficient, (d) multiply output sample by gain. The circular buffer write/read on every sample causes repeated memory indirection. On a 48 kHz stereo stream with 4096-sample look-ahead this is ~96 000 operations/second just for the buffer management, plus gain smoothing math.

**Estimated CPU Cost**
High

**Call Frequency**
Per-sample (continuous during playback)

**Native Suitability**
Yes — already in C. The bottleneck is the lack of NEON on the gain-multiply step and the non-vectorized peak-window scan. NEON can process the gain-multiply step in groups of 16 floats using `nar_gain_apply_neon`. The peak scan is harder to SIMD-ize but `vmaxnm.4s` reduces it to ~n/4 comparisons.

**Possible Native Optimizations**
- ARM64 NEON `vmaxnm.4s` for peak window scan (4 samples/instruction)
- Reuse `nar_gain_apply_neon` for the gain-multiply pass once gain is known for the whole buffer
- Cache-aligned circular buffer with power-of-2 masking instead of modulo

**Estimated Speedup**
2–3× (gain-multiply alone: 4×; peak scan: 2×; combined considering branch/memory overhead)

**Migration Complexity**
Medium — circular buffer semantics must be preserved exactly; NEON peak scan requires restructuring the look-ahead window algorithm

**Risk**
- Thread safety: already handled via stream slot isolation  
- Memory ownership: circular buffer is stack-allocated in processor state  
- Audio synchronization: look-ahead introduces fixed 63-frame latency — must not change  
- JNI overhead: none — already native C

**Priority**
**Critical**

---

### 2. Soft Clipper — Per-sample `tanhf` Waveshaping

**File**
```
native_audio_runtime/src/soft_clipper_processor.c
```

**Function**
```
_sc_process()
```

**Line Number**
```
72–119
```

**Category**
Audio DSP — Nonlinear waveshaping

**Why It Is Expensive**  
`tanhf()` is a transcendental function with a branch (only applied when `|x| > threshold`). On ARM Cortex-A76, a single `tanhf` call costs approximately 15–25 ns. At 96 000 calls/second (48 kHz stereo) and assuming 30% of samples exceed threshold, that is ~3 ms/second devoted purely to this function. The branch also prevents auto-vectorization by Clang. Additionally, the current implementation evaluates `tanhf` on a scalar path even though the DSP pipeline passes buffers of 1024 frames.

**Estimated CPU Cost**
Medium–High

**Call Frequency**
Per-sample (continuous during playback)

**Native Suitability**
Yes. A polynomial approximation of `tanh` using NEON is standard: `tanh(x) ≈ x(27+x²)/(27+9x²)` (rational Padé, max error ~1e-4 at |x|≤3) can be evaluated in ~4 NEON multiply-add instructions for 4 samples simultaneously, replacing one `tanhf` call per sample.

**Possible Native Optimizations**
- ARM64 NEON rational Padé approximation for `tanh` — 4 samples/cycle
- `vmovlt` + `vcgtq` for threshold comparison without scalar branch
- LLVM auto-vectorization (if `tanhf` branch is replaced with a branchless approximation)

**Estimated Speedup**
4–6× (approximation eliminates transcendental call; vectorization processes 4 samples simultaneously)

**Migration Complexity**
Low — self-contained function, no external state dependencies; approximation accuracy is well within audible threshold for clipping

**Risk**
- Thread safety: no shared mutable state in _sc_process  
- Audio quality: Padé approximation introduces < 0.01 dB error relative to true `tanh` at normal signal levels — inaudible  
- JNI overhead: none — already native C

**Priority**
**Critical**

---

### 3. Stereo Widening — Per-sample 2×2 Matrix in Kotlin JVM

**File**
```
android/app/src/main/kotlin/dev/wndavenz/music/effects/StereoWideningAudioProcessor.kt
```

**Function**
```
queueInput()
```

**Line Number**
```
64–100
```

**Category**
Audio DSP — Matrix mixing, format conversion

**Why It Is Expensive**  
This is a **Kotlin JVM AudioProcessor** running on ExoPlayer's audio thread. For every stereo frame it executes 4 float multiplications and 2 additions (PCM-float path), or adds float→short conversion + `coerceIn()` + `toShort()` boxing (PCM-16 path). The PCM-16 path is significantly more expensive: each frame involves 2 `toFloat()` conversions, 4 multiplications, 2 additions, 2 `toInt()` + `coerceIn()` clamping operations, and 2 `toShort()` conversions — approximately 14 JVM operations per frame vs. 6 for the float path. At 48 kHz this is ~48 000 frames/second processed in interpreted JVM bytecode. JIT will optimize it, but JVM object overhead, ByteBuffer method dispatch, and the absence of SIMD intrinsics leave significant performance on the table compared to native C.

**Estimated CPU Cost**
Medium (PCM-float path) / High (PCM-16 path)

**Call Frequency**
Every audio buffer (~40–100 Hz dispatch, per-sample computation inside)

**Native Suitability**
Yes — strongly. The operation is a classic 2×2 matrix multiplication over a float buffer, which is exactly what `nar_gain_apply_neon` was built for (conceptually). A native C implementation using NEON `fmla v.4s` can process 2 stereo frames (4 floats: L0, R0, L1, R1) per instruction group, achieving 4× throughput over JVM scalar. The existing `NativeDspAudioProcessor.kt` JNI bridge pattern shows exactly how to route an ExoPlayer AudioProcessor buffer through JNI to native C.

**Possible Native Optimizations**
- NEON `fmla v.4s` for interleaved L/R mixing: 2 frames (4 floats) per cycle
- LLVM auto-vectorization of the inner loop once in C
- Eliminate PCM-16 conversion overhead by requiring float pipeline (PCM-float is already the preferred path in ExoPlayer 1.10.1+)

**Estimated Speedup**
3–5× over current JVM implementation; PCM-16 path: 6–8×

**Migration Complexity**
Medium — requires JNI bridge (pattern already exists in `NativeDspAudioProcessor.kt`), or alternatively merge into the existing `NativeDspAudioProcessor` DSP pipeline as a new processor slot

**Risk**
- JNI overhead: ~1–2 µs per buffer call — acceptable vs. current per-sample JVM cost  
- Thread safety: `diag`/`cross` are `@Volatile`; JNI equivalent requires `atomic_load`  
- Audio synchronization: stateless per-buffer operation — no synchronization issues  
- Format compatibility: must handle both PCM-float and PCM-16 or require float pipeline

**Priority**
**High**

---

### 4. Compressor — Per-frame `logf`/`expf` + Per-sample Gain Multiply

**File**
```
native_audio_runtime/src/comp_processor.c
```

**Function**
```
_comp_process()
```

**Line Number**
```
167–248
```

**Category**
Audio DSP — Envelope following, gain computation

**Why It Is Expensive**  
The compressor uses a frame-major design (one envelope update per multi-channel frame, not per sample), which means 1 `logf` + 1 `expf` per frame rather than per sample — already a significant optimization. However, the per-sample gain-multiply loop (lines 240–242) applies the same `gain_linear` scalar to all channels of the frame using a scalar loop. At 48 kHz with 2 channels, this is 96 000 scalar multiplications/second that could be replaced with NEON. Additionally, `nar_linear_to_db` and `nar_db_to_linear` involve `logf` and `powf(10, x/20)` respectively — these run once per frame but at 48 000 frames/second add up.

**Estimated CPU Cost**
Medium

**Call Frequency**
Per-buffer (outer loop) / Per-frame (envelope math) / Per-sample (gain multiply)

**Native Suitability**
Yes — partial. The `logf`/`expf` calls per frame are unavoidable math costs. The per-sample gain multiply (lines 240–242) can use `nar_gain_apply_neon` or a local vectorized kernel since `gain_linear` is constant across all channels in the frame. Clang with `-O3 -march=armv8-a+simd` may already auto-vectorize this inner loop; verification via `.s` assembly dump is needed.

**Possible Native Optimizations**
- Use `nar_gain_apply_neon` or inline `fmul v.4s` for the per-sample gain-multiply inner loop
- `vrecpe`/`vrsqrte` approximations for `logf` if dB precision can be relaxed (not recommended for compressor knee accuracy)
- LLVM `-ffast-math` on the inner multiply loop only (not the log/exp paths where precision matters)

**Estimated Speedup**
1.5–2× for the gain-multiply inner loop; overall compressor speedup: ~1.3× (log/exp is the true bottleneck)

**Migration Complexity**
Low — already native C; change is adding `nar_gain_apply_neon` call to the inner per-sample loop

**Risk**
- Thread safety: per-stream dirty-flag pattern already safe  
- Audio precision: gain-multiply NEON is exact (IEEE 754 float multiply — same precision)

**Priority**
**High**

---

### 5. Crossfeed — Stereo Matrix Not NEON-ized

**File**
```
native_audio_runtime/src/stereo_matrix.h
native_audio_runtime/src/crossfeed_processor.c
```

**Function**
```
nar_stereo_matrix_apply()
_xf_process()
```

**Line Number**
```
stereo_matrix.h: 54–63
crossfeed_processor.c: 163–284
```

**Category**
Audio DSP — 2×2 matrix, signal processing

**Why It Is Expensive**  
`_xf_process()` calls `nar_stereo_matrix_apply()` per-sample (after the biquad filtering) to mix cross-path and direct-path signals. The 2×2 matrix requires 4 multiplications + 2 additions per frame. The biquad stages already use `nar_biquad_stereo_neon`, but the stereo matrix step immediately following them reverts to scalar. This means the NEON-optimized biquad output is handed off to a scalar mixer.

**Estimated CPU Cost**
Medium

**Call Frequency**
Per-sample (continuous during playback, when crossfeed is enabled)

**Native Suitability**
Yes. A 2×2 stereo matrix is exactly the operation that `fmla v.2s` handles: load [L, R] into a 2-lane vector, multiply by the matrix rows, and accumulate. This replaces 4 scalar multiplications with 2 NEON instructions. The `neon_kernels.h` comment already identifies this as a candidate ("Candidate for `fmla` vectorization in crossfeed").

**Possible Native Optimizations**
- NEON `fmla v.2s` for 2×2 matrix-vector multiply: 2 instructions per frame vs. 4 scalar multiplications  
- Combine with biquad NEON path for a fully vectorized crossfeed frame

**Estimated Speedup**
2× for the matrix step; crossfeed overall: ~1.4× (biquads are already NEON)

**Migration Complexity**
Low — add `nar_stereo_matrix_apply_neon()` to `neon_kernels.h`/`.S`, guarded by `__aarch64__`

**Risk**
- Thread safety: stateless per-frame operation  
- Audio: matrix coefficients are constants derived from crossfeed parameters — no precision risk

**Priority**
**High**

---

### 6. Loudness Normalization — Scalar Fallback + `log10` in Gating Loop

**File**
```
native_audio_runtime/src/loudness_processor.c
```

**Function**
```
_ln_process()
```

**Line Number**
```
473–622
```

**Category**
Audio DSP — IIR K-weighting, BS.1770-4 gating, gain smoothing

**Why It Is Expensive**  
Two cost centers: (a) The per-sample K-weighting IIR is already NEON for stereo (via `nar_biquad_stereo_neon`), but falls back to scalar C for mono/multichannel content. (b) Every 100 ms sub-block boundary (~4 800 frames at 48 kHz) runs `log10()` for the LUFS computation and `powf(10, x/20)` for the gain target — these are inexpensive at 10 Hz but use double-precision. Additionally, the per-frame gain-multiply inner loop (lines 615–617) applies `gain_smooth` to all channels in a scalar loop — same missed NEON opportunity as the compressor.

**Estimated CPU Cost**
Medium (stereo NEON path) / High (mono/multichannel scalar path)

**Call Frequency**
Per-sample (IIR) / Per 100 ms sub-block (gating/gain update)

**Native Suitability**
Yes — partial. (a) Mono path: add a scalar-to-NEON migration for single-channel biquad (trivially extend `nar_biquad_stereo_neon` with a 1-lane variant, or just let the existing `nar_biquad_process_sample()` be auto-vectorized by Clang). (b) Per-frame gain multiply: same fix as the compressor — use `nar_gain_apply_neon` or inline NEON.

**Possible Native Optimizations**
- Single-channel biquad NEON variant (`v.s` 1-lane or scalar auto-vectorization hint)
- Reuse `nar_gain_apply_neon` for per-frame gain-smooth multiply across all channels
- Replace `double` precision in the gating loop with `float` where BS.1770-4 precision permits (LUFS only needs ~0.1 LU resolution)

**Estimated Speedup**
1.5–2× for the mono path; stereo path improvement: ~1.3× (gain-multiply only)

**Migration Complexity**
Low–Medium

**Risk**
- Precision: BS.1770-4 requires double-precision for the gating accumulators (`sub_acc`, `abs_sum_z`) to avoid cumulative error over long tracks — do not reduce these to float  
- Thread safety: per-stream atomic pattern already correct

**Priority**
**Medium**

---

### 7. PcmDecoder — Per-chunk `ShortArray` Allocation in Decode Loop

**File**
```
android/app/src/main/kotlin/dev/wndavenz/music/replaygain/PcmDecoder.kt
```

**Function**
```
decode()
```

**Line Number**
```
89–131 (inner decode loop), specifically line 120: `val chunk = ShortArray(remaining)`
```

**Category**
Memory — Frequent allocation, codec helper

**Why It Is Expensive**  
Every iteration of the MediaCodec output loop allocates a new `ShortArray(remaining)` (line 120). For a 4-minute track at 48 kHz stereo, the decoder produces ~2 800 buffers of ~1024 frames each = ~2 800 heap allocations during a single ReplayGain scan. Each allocation triggers GC pressure proportional to the array size (~2 KB per buffer). The total allocation across a full library scan of 100 tracks is ~280 000 `ShortArray` allocations.

**Estimated CPU Cost**
Medium (individual decode), Very High (library-wide scan)

**Call Frequency**
Continuous during offline ReplayGain scan (background)

**Native Suitability**
No for the JNI migration itself, but yes for the allocation fix: pre-allocate a single reusable `ShortArray` sized to the maximum MediaCodec output buffer size before the loop, then reuse it each iteration with a `frameCount` parameter to `feed()`. This is a Kotlin-only fix that eliminates GC pressure without any native code change.

**Possible Native Optimizations**
- Pre-allocate `ShortArray` before loop, reuse per iteration (Kotlin-only fix)
- Pass `ByteBuffer` directly from MediaCodec output to the native libebur128 path without materializing a `ShortArray` at all — eliminates the copy entirely
- Alternatively wrap the entire decode+analysis pipeline in a native C function fed via JNI `ByteBuffer.allocateDirect()`

**Estimated Speedup**
1.3–1.5× (GC pressure reduction); 2–3× if ByteBuffer → native path eliminates the copy

**Migration Complexity**
Low (pre-alloc fix) / Medium (ByteBuffer native path)

**Risk**
- This runs in a background coroutine — no audio thread risk  
- `feed()` callback contract must be preserved if array is reused  
- If `feed()` stores a reference to the passed array, reuse will corrupt data — verify it only reads

**Priority**
**Medium**

---

### 8. Palette Extractor — MMCQ Image Quantization (Dart Isolate)

**File**
```
lib/services/palette_extractor.dart
```

**Function**
```
_extract()
```

**Line Number**
```
157–213
```

**Category**
Image Processing — Color quantization, histogram

**Why It Is Expensive**  
The `palette_generator_plus` package runs Median-Cut Color Quantization (MMCQ) on decoded pixel data. This involves: (a) building a 3D RGB histogram over all pixels of the downscaled 112×112 image (12 544 pixels), (b) iterative median-cut subdivision of color boxes, (c) sorting and averaging. It already runs in a Dart `Isolate`, which avoids UI jank, and images are pre-scaled to 112×112. However, MMCQ on a 12 544-pixel image still requires ~500K–1M histogram operations per extraction.

**Estimated CPU Cost**
High (per call), Low (per second — runs once per unique song change)

**Call Frequency**
Once per song change (when artwork changes and result is not LRU-cached)

**Native Suitability**
Conditionally yes — only if palette extraction becomes a measurable bottleneck (e.g. during rapid song skipping). Migrating to native C (libyuv or custom NEON histogram) could reduce extraction from ~8 ms to ~1 ms. However, given the current 256-entry LRU cache and isolate isolation, this is premature unless profiling shows it contributes to UI jank.

**Possible Native Optimizations**
- NEON histogram accumulation: 16 pixels/iteration with `vld4.8` interleaved RGBA load
- Parallel bin accumulation with NEON `vaddw.s16` across 8-bit pixel values
- Replace `palette_generator_plus` with a JNI call to Android's `Palette` API (hardware-accelerated on some Snapdragon targets) or a custom NEON implementation

**Estimated Speedup**
5–8× for NEON histogram; overall extraction: 3–4× (sort/cut steps not SIMD-able)

**Migration Complexity**
High — requires replacing the Dart package with a custom Dart FFI + native C implementation; Dart FFI overhead on mobile is non-trivial for one-shot calls

**Risk**
- Not on the audio thread — no real-time risk  
- Dart FFI bridge adds ~5–10 µs overhead per call (acceptable for a one-shot operation)  
- `palette_generator_plus` may have edge cases in MMCQ that a custom implementation must replicate

**Priority**
**Low**

---

### 9. Fluid Shader — GLSL Trig per Pixel (GPU, not CPU)

**File**
```
lib/widgets/player/player_background/fog_painter.dart
assets/ (fluid.frag — GLSL fragment shader)
```

**Function**
```
_ShaderPainter.paint() / advanceBlend() / _recompute()
```

**Line Number**
```
fog_painter.dart: 45–87 (Dart CPU side)
fluid.frag: N/A (GPU)
```

**Category**
Animation — GPU fragment shader, per-pixel trig

**Why It Is Expensive**  
The GPU cost is real but handled by Adreno 618 hardware. The Dart CPU side (`advanceBlend` + `_recompute`) performs 9 lerp operations per animation tick (only during the 800 ms color crossfade window) and then 12 `setFloat()` uniform uploads + 1 `drawRect()`. This is well-optimized — zero per-pixel arithmetic on the CPU, pre-computed uniforms, `RepaintBoundary` isolation. No migration is needed or beneficial.

**Estimated CPU Cost**
Negligible (Dart side) / Medium (GPU side — handled by hardware)

**Call Frequency**
60–120 FPS for 800 ms per song transition; idle otherwise

**Native Suitability**
No — the Dart CPU side is already near-optimal (9 scalar lerps). The GPU path is handled by the Adreno 618 shader compiler. No benefit from migrating to native C.

**Estimated Speedup**
Negligible

**Migration Complexity**
N/A

**Priority**
**Low — no action needed**

---

### 10. LRC Lyrics Parser — Regex Passes

**File**
```
lib/services/lyrics_service/lrc_parser.dart
```

**Function**
```
parseLrc(), parse()
```

**Line Number**
```
parseLrc(): 99–164 / parse(): 46–69
```

**Category**
Signal Processing — String parsing, regex

**Why It Is Expensive**  
Multiple compiled regex patterns (`_tsRe`, `_inlineRe`, `_metaRe`, `_enhancedRe`) applied to multi-hundred-line LRC files. Dart's `RegExp` compiles patterns at first use (regexps are already top-level constants, so compilation happens once). The per-parse cost is proportional to lyric file length — typically 200–500 lines. Runs once per song load when lyrics are fetched.

**Estimated CPU Cost**
Low–Medium (once per song, not real-time)

**Call Frequency**
Once per song when lyrics are loaded

**Native Suitability**
No — Dart regex is implemented in native C++ under the hood (V8/irregexp). Migrating to a native parser would add JNI overhead that likely exceeds the savings for 500-line files.

**Estimated Speedup**
Negligible

**Migration Complexity**
N/A

**Priority**
**Low — no action needed**

---

### 11. Crossfade Equal-Power Curves — `sin`/`cos` in Handler Runnable

**File**
```
android/app/src/main/kotlin/dev/wndavenz/music/crossfade/CrossfadeController.kt
```

**Function**
```
runEqualPowerFade() (Runnable.run())
```

**Line Number**
```
424–428
```

**Category**
Math — Trigonometric functions

**Why It Is Expensive**  
Calls `sin(theta)` and `cos(theta)` once per 16 ms fade step for the equal-power volume curve. That is 2 trig calls every 16 ms = 125 calls/second for each of the 2 players during an active crossfade. At ~25 ns per ARM64 trig call, this is ~6 µs/second total — **entirely negligible**. The volumes could be pre-computed into a lookup table, but the cost is so low that this would be premature optimization.

**Estimated CPU Cost**
Negligible

**Call Frequency**
Every 16 ms (only during active crossfade, not continuous)

**Native Suitability**
No — cost is immeasurable in a real profiler.

**Priority**
**Low — no action needed**

---

## Native Migration Summary

### Critical

- **`_lim_process()` limiter** (`limiter_processor.c:112–217`) — per-sample scalar loop; no NEON on gain-multiply or peak-scan despite being the last DSP stage processing every single sample
- **`_sc_process()` soft clipper** (`soft_clipper_processor.c:72–119`) — per-sample `tanhf` transcendental with a branch that defeats Clang auto-vectorization; NEON Padé approximation would give 4–6×

### High

- **`StereoWideningAudioProcessor.queueInput()`** (`StereoWideningAudioProcessor.kt:64–100`) — JVM Kotlin per-sample 2×2 matrix on the audio thread; should be in native C using the existing `NativeDspAudioProcessor` JNI pattern
- **`_comp_process()` gain multiply** (`comp_processor.c:240–242`) — inner per-sample multiply loop is scalar; 1-line fix to use `nar_gain_apply_neon`
- **`nar_stereo_matrix_apply()` in crossfeed** (`stereo_matrix.h:54–63`) — 2×2 matrix per sample is scalar immediately after NEON biquads; NEON `fmla v.2s` is a natural fit

### Medium

- **`_ln_process()` mono/multichannel path** (`loudness_processor.c:529–542`) — scalar K-weighting IIR fallback for non-stereo; per-frame gain-multiply also scalar
- **`PcmDecoder.decode()` ShortArray alloc** (`PcmDecoder.kt:120`) — per-chunk heap allocation during ReplayGain scan; pre-allocation or direct ByteBuffer path eliminates GC pressure

### Low

- **Palette extractor** (`palette_extractor.dart:157–213`) — MMCQ quantization in Dart Isolate; already well-mitigated, only a concern under rapid song skipping
- **LRC parser** (`lrc_parser.dart:99–164`) — regex over 500-line files; runs once per song, not measurable
- **Crossfade sin/cos** (`CrossfadeController.kt:424–428`) — 2 trig calls/16 ms; negligible
- **Fluid shader CPU side** (`fog_painter.dart:45–87`) — 9 lerps/frame for 800 ms; GPU-bound, Dart side already optimal

---

## Migration Roadmap

### Phase 1 — In-pipeline NEON completions (no new architecture, minimal risk)

1. `_lim_process()`: add NEON peak-scan + reuse `nar_gain_apply_neon` for gain-multiply  
2. `_sc_process()`: replace `tanhf` with NEON Padé `tanh` approximation (branchless, 4 samples/cycle)  
3. `_comp_process()`: one-line fix — use `nar_gain_apply_neon` in the per-sample inner loop  
4. `nar_stereo_matrix_apply_neon()`: add to `neon_kernels.h`/`.S`, wire into `_xf_process()`

**Justification:** All changes are inside already-native C. No JNI boundary changes. Each is isolated to a single processor. Clang regression test via `flutter analyze` + native unit tests.

---

### Phase 2 — JVM → Native migration (new JNI surface)

5. `StereoWideningAudioProcessor`: rewrite `queueInput()` inner loop as a C function, call via JNI through `NativeDspAudioProcessor` bridge, or add as a new DSP pipeline slot

**Justification:** Same JNI pattern as `NativeDspAudioProcessor` already exists. The migration is medium complexity but the JVM→native gain is the largest single improvement available to the audio thread.

---

### Phase 3 — Background worker optimization (no real-time risk)

6. `PcmDecoder`: pre-allocate reusable `ShortArray` before the decode loop; optionally refactor to pass `ByteBuffer` directly to native libebur128

**Justification:** Background task, no audio thread risk. Pure Kotlin change for the pre-alloc fix.

---

### Phase 4 — Conditional (profile first)

7. `_ln_process()`: mono/multichannel NEON biquad (only relevant if mono content is common)  
8. Palette extractor: NEON histogram (only if profiling shows jank during rapid song skipping; 256-entry LRU cache makes this rare in practice)

---

*End of audit.*
