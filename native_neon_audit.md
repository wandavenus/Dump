# Native Code Audit — ARM64 NEON Intrinsics Optimization

**Date:** 2026-10-26  
**Project:** `musicplayer` (`dev.wndavenz.music`)  
**App version:** `1.5.48` (`pubspec.yaml:4`)  
**Commit:** `c03aec9` (`Create brief.md`)  
**Target device:** Xiaomi Mi 9T / Redmi K20, arm64-v8a, Android 11 / MIUI 12  
**Scope:** native C, ARM64 assembly, JNI/FFI boundaries, Android/native-assets build, native tests and benchmarks, and the production call paths that reach them  
**Status:** static audit complete; performance validation pending; **no production code changed**

> **Bottom line:** the live audio DSP is already SIMD-aware and should not be rewritten without measurement. The only defensible NEON program is the **offline AutoMix analysis pipeline** — shared FFT, main magnitude/feature pass, and the separate chord pass. Even there, a stage-level benchmark and generated-assembly inspection must come first, because the compiler may already auto-vectorize parts of the scalar source.

---

## 0. Method and limitations

### 0.1 Method

The audit was performed against the actual source and call paths, not against assumptions:

1. Traced the real-time path from `NativeDspAudioProcessor`/JNI into the C DSP pipeline.
2. Traced the offline AutoMix path from Kotlin `AutomixAnalysis` through the PCM downsampler and JNI into `automix_analyzer.c`.
3. Inventoried every native processor, AutoMix module, NEON kernel, JNI bridge, and relevant build file.
4. Compared current SIMD coverage with the hot loops and data layouts.
5. Checked the existing native tests and benchmark harness.
6. Estimated static work counts where possible (frames, FFTs, bins, JNI bytes); **no timing claim is made**.

“NEON” in this report means ARM Advanced SIMD. Existing code uses NEON through hand-written `.S` assembly; the proposed changes would use C intrinsics from `<arm_neon.h>` unless stated otherwise.

### 0.2 Limitations

| Limitation | Effect on this audit |
|---|---|
| No Android Gradle/CMake build was run | The shipped arm64 library was not inspected; compiler auto-vectorization and final instruction selection are unknown. |
| No on-device profiling | CPU time, memory bandwidth, cache behavior, thermal throttling, and end-to-end AutoMix latency are unmeasured. All benefit estimates are hypotheses. |
| Native Dart/FFI tests could not load in this environment | `dart test test/automix_native_test.dart test/native_audio_runtime_test.dart` and `dart test test/native_benchmark.dart -r expanded` fail at `dlopen` with `cannot locate symbol "__android_log_print"` in `.dart_tool/lib/libnative_audio_runtime.so`. This is a host/native-assets loader issue in this Termux environment, not evidence that the C code fails on Android. No test result from this session is used as a performance baseline. |
| No disassembly of the shipped library | “Scalar source” does not imply “scalar machine code.” Clang may auto-vectorize portions of the magnitude, gain, and biquad loops. |
| Build optimization flags are not fully explicit in the repo | The native-assets hook and the ReplayGain CMake target do not state `-O3` or `-march=armv8-a+simd`; repo memory claims those flags exist. Actual compile commands must be captured before benchmarking. |
| AutoMix is offline | Analyzer improvements affect background analysis latency/cache fill, not the audio callback deadline. This reduces urgency relative to a real-time DSP miss. |

### 0.3 Scale inspected

| Metric | Value |
|---|---:|
| Native C/header/assembly files in `native_audio_runtime/src` | 46 |
| Lines in those files | 10,419 |
| C++/headers under `android/app/src/main/cpp` | 10 |
| Lines across `replaygain/*.cpp` and `stretch/*.cpp` | 2,148 |
| Explicit NEON kernels in production use | 4 |
| AutoMix analysis passes | 2 (main features; chord progression) |
| Measured benchmarks obtained in this session | 0 |
| Confirmed functional defects from static inspection | 0 |

### 0.4 Evidence levels

- **Confirmed:** verified in source/configuration with a file and line reference.
- **Likely:** follows from the code and known toolchain behavior, but not disassembled or measured.
- **Hypothesis:** expected performance outcome; requires profiling.

The candidate benefits below are mostly **Hypothesis** even when the current implementation is **Confirmed** scalar source.

---

## 1. Executive summary

1. **The real-time DSP chain does not offer a high-confidence NEON win.** Gain, ReplayGain, crossfeed, loudness K-weighting, AutoMix tone, and AutoMix window/RMS already use NEON. The remaining scalar loops are either serial-state, branchy, tiny, or already partially auto-vectorized.
2. **The only substantial unvectorized DSP is offline AutoMix analysis.** At 300 s and 22.05 kHz, the main analyzer and chord pass together perform approximately **31,900 2048-point FFTs** and **26 million magnitude evaluations**. At the maximum 900 s window the counts rise to approximately **95,900 FFTs** and **78 million magnitudes**.
3. **The FFT is the largest single static target.** `radix2_fft()` is shared by the main STFT, the cepstrum, and the chord pass. It is scalar C with a separate bit-reversal pass and per-butterfly twiddle lookup.
4. **The main magnitude/feature pass is the second target.** It performs `sqrtf` + `logf` per bin, branchy vocal-band checks, spectral flux, centroid accumulation, and HPCP folding. There is no hardware vector `log`, so vectorizing only the square root/sums leaves `logf` scalar unless a validated approximation is introduced.
5. **The chord pass is not negligible.** It adds ~12,558 FFTs and ~12.9 million double-precision `hypot()` calls at 300 s. It was previously easy to underestimate because it runs “separately” from the main analyzer, but it runs on the same 300 s PCM window.
6. **Do not start by modifying real-time processors.** The live tracker, compressor, limiter, soft clipper, planner, and pipeline wrappers are all poor NEON candidates for concrete reasons documented below.
7. **The first engineering task is instrumentation, not optimization.** There is no per-stage analyzer benchmark, no direct scalar-vs-NEON parity test for FFT/magnitude, and no confirmation of actual compiler flags or auto-vectorization.

### Decision

Proceed only with a **measurement-gated offline AutoMix optimization program**. If a stage benchmark shows no material win, or output parity cannot be maintained, stop. Do not convert any real-time path in this pass.

---

## 2. Architecture and build context

### 2.1 Offline AutoMix analysis path

```text
AutomixAnalysis.analyze()
  └─ PcmDecoder.decode()
      └─ AutomixPcmDownsampler.processFrame()       Kotlin, per source frame
          └─ mono FloatArray at 22.05 kHz
              ├─ AutomixNative.nativeAnalyzeCentered()  JNI
              │   └─ automix_jni.cpp
              │       └─ nar_automix_analyze_centered()
              │           └─ analyze_impl()             automix_analyzer.c
              └─ AutomixNative.nativeAnalyzeChords()    JNI
                  └─ nar_automix_analyze_chords()       automix_analyzer.c
```

Key production parameters:

- `MAX_ANALYZE_SECONDS = 300` (`AutomixAnalysisBridge.kt:37`)
- `TARGET_RATE_HZ = 22050` (`AutomixAnalysisBridge.kt:38`)
- `MAX_WINDOW_SECONDS = 900` (`AutomixAnalysisBridge.kt:40`)
- The analyzer requires at least 1 s of PCM; analysis below that returns failure.
- The main analyzer produces 32 doubles (`NAR_AUTOMIX_ANALYSIS_VALUE_COUNT`); the chord pass returns rows of four doubles.
- Both native passes use the same `monoPcm` Java array (`AutomixAnalysisBridge.kt:142-161`), but JNI may copy the array separately for each call.

### 2.2 Real-time DSP path

```text
Media3PlaybackService
  └─ NativeDspAudioProcessor (Kotlin/JNI)
      └─ native_dsp_jni.c
          ├─ nar_automix_live_tracker_process()   when AutoMix is active
          └─ nar_dsp_pipeline_process()
              ├─ gain
              ├─ replaygain
              ├─ crossfeed
              ├─ loudness
              ├─ compressor
              ├─ limiter
              ├─ soft clipper
              ├─ acoustic engine
              └─ AutoMix tone / true-peak limiter
```

The live tracker is called from `native_dsp_jni.c:90-91`; AutoMix tone is configured and processed through the same JNI layer. These are audio-thread paths and have a stricter risk profile than offline analysis.

### 2.3 Build and ABI

| Item | Current state | Evidence |
|---|---|---|
| Android ABI | arm64-v8a only | `android/app/build.gradle:85`, `:103` |
| `minSdk` | 29 | `android/app/build.gradle:79` |
| `targetSdk` / `compileSdk` | 36 / 36 | `android/app/build.gradle:50`, `:80` |
| NDK | `28.2.13676358` | `android/app/build.gradle:51` |
| Native-assets sources | Includes `neon_kernels.S`, `automix_neon.S`, `automix_tone_neon.S` | `native_audio_runtime/hook/build.dart:53-83` |
| Android-only JNI source | `native_dsp_jni.c` | `native_audio_runtime/hook/build.dart:67-70` |
| Android CMake | Builds `replaygain_native` with analyzer, planner, phase lock, `automix_neon.S`; builds `stretch_native` separately | `android/app/src/main/cpp/CMakeLists.txt:62-91`, `:160-170` |
| Phase-lock ownership | `automix_phase_lock.c` is in the Android CMake library, not the native-assets hook | `android/app/src/main/cpp/CMakeLists.txt:70`; `automix_jni.cpp:5` |
| Optimization flags | Not explicit in the native-assets hook; ReplayGain CMake has no `-O3`/`-march`; Stretch has `-O3` | `hook/build.dart`; `CMakeLists.txt:91`, `:167`; repo memory `native-runtime-internals.md:20` claims `-O3`, `-march=armv8-a+simd` |

**Build note:** `automix_analyzer.c` is compiled into both `libnative_audio_runtime.so` (Dart FFI) and `libreplaygain_native.so` (JNI). They are separate libraries, so there is no duplicate-symbol issue, but they may receive different compiler flags. Benchmark both production entry points or verify that both builds use equivalent flags.

`automix_phase_lock.c` is intentionally Android/JNI-only; it is not a missing native-assets source. Do not “fix” it by adding it to `hook/build.dart` unless a Dart FFI entry point is added later.

---

## 3. Inventory

### 3.1 Real-time DSP chain

| Component | File | Role | Current SIMD state | Verdict |
|---|---|---|---|---|
| Gain | `native_audio_runtime/src/gain_processor.c` | Linear gain multiply | `nar_gain_apply_neon()`, 16 samples/iteration (`:108`) | Preserve |
| ReplayGain | `native_audio_runtime/src/replaygain_processor.c` | ReplayGain gain multiply | Same NEON kernel (`:136`) | Preserve |
| Biquad helper | `native_audio_runtime/src/biquad_filter.c/.h` | Coefficient/sample biquad | Scalar helper; used by NEON stereo kernel | Preserve |
| Crossfeed | `native_audio_runtime/src/crossfeed_processor.c` | Stereo crossfeed | Two `nar_biquad_stereo_neon()` calls/frame (`:239`, `:245`) | Preserve |
| Loudness | `native_audio_runtime/src/loudness_processor.c` | K-weighting / BS.1770-4 | Stereo NEON K-weight cascade (`:450-463`, call `:523`) | Preserve |
| Compressor | `native_audio_runtime/src/comp_processor.c` | Serial compressor | Scalar per-frame `logf`/`expf`, linked envelope (`:209-250`) | Do not convert |
| Limiter | `native_audio_runtime/src/limiter_processor.c` | Look-ahead limiter | Scalar serial state machine (`:159-240`) | Do not convert |
| Soft clipper | `native_audio_runtime/src/soft_clipper_processor.c` | `tanh`-style clip | Branchy scalar; transparent path compiler-vectorizable (`:119-140`) | Do not convert |
| Acoustic Engine | `native_audio_runtime/src/acoustic_engine_processor.c` | 5-biquad speaker enhancement | Scalar; five biquads per channel/frame (`:183-205`) | Investigate only |
| AutoMix tone | `native_audio_runtime/src/automix_tone_processor.c` | Low/mid/high/fade | Stereo NEON tone path (`:381-389`); true peak scalar (`:262-354`) | Preserve; true peak conditional |
| Live tracker | `native_audio_runtime/src/automix_live_tracker.c` | Real-time BPM/phase | Scalar per-sample and FP64 autocorrelation (`:517-631`) | Do not convert |
| AutoMix analyzer | `native_audio_runtime/src/automix_analyzer.c` | Offline features/chords | Window/RMS NEON (`:763`); rest scalar | Primary candidate |
| Planner | `native_audio_runtime/src/automix_planner.c` | Playlist ordering | Scalar combinatorial search (`:974-1060`) | Do not convert |
| Pipeline | `native_audio_runtime/src/dsp_pipeline.c` | Processor chain | Scalar orchestration | Do not convert |
| Audio buffer | `native_audio_runtime/src/audio_buffer.c` | Interleaved buffer views | Scalar pointer/stride logic | Do not convert |

### 3.2 NEON assets and boundaries

| Component | File | Role | Current state | Verdict |
|---|---|---|---|---|
| Gain/biquad assembly | `native_audio_runtime/src/neon_kernels.S`, `.h` | `nar_gain_apply_neon`, `nar_biquad_stereo_neon` | Live NEON assembly | Preserve |
| AutoMix window/RMS | `native_audio_runtime/src/automix_neon.S` | Windowed frame + sum of squares | Live NEON assembly | Preserve |
| AutoMix tone | `native_audio_runtime/src/automix_tone_neon.S` | Stereo tone/fade path | Live NEON assembly | Preserve |
| Phase lock | `native_audio_runtime/src/automix_phase_lock.c` | AutoMix phase-lock math | Scalar; Android CMake only | No NEON case |
| DSP JNI | `native_audio_runtime/src/native_dsp_jni.c` | PCM/control JNI | No DSP loops | Boundary only |
| AutoMix JNI | `android/app/src/main/cpp/replaygain/automix_jni.cpp` | Analysis/chord JNI | `GetFloatArrayElements` at `:15`, `:87` | Non-SIMD boundary |
| Analysis bridge | `android/app/src/main/kotlin/dev/wndavenz/music/automix/AutomixAnalysisBridge.kt` | Decode/analyze orchestration | Kotlin; 300 s/22.05 kHz | Boundary only |
| PCM downsampler | `android/app/src/main/kotlin/dev/wndavenz/music/automix/AutomixPcmDownsampler.kt` | Source-rate mono downsample | Kotlin per-frame; double Butterworth | Non-SIMD boundary |

---

## 4. Positive findings

### P-01 — Existing NEON is live and at the intended call sites

- `nar_gain_apply_neon()` is used by both gain and ReplayGain, not orphaned.
- `nar_biquad_stereo_neon()` is used by crossfeed and loudness K-weighting, exactly where the two-channel parallel form pays off.
- `nar_automix_tone_process_stereo_neon()` is used for the stereo AutoMix tone path.
- `nar_automix_window_rms_neon()` is used for the analyzer’s windowed frame and RMS.

This matters because a common audit failure is to recommend vectorizing code that already has a dormant NEON implementation. That is not the case here.

### P-02 — Gain path is already wide

`nar_gain_apply_neon()` processes **16 floats per main iteration** with four `fmul v.4s` operations, plus tail loops (`neon_kernels.S:48-108`). Replacing it with scalar C intrinsics would not be an improvement.

### P-03 — Stereo biquad kernel is used correctly

`nar_biquad_stereo_neon()` processes two independent channel states through one shared coefficient set (`neon_kernels.S:151-204`). Crossfeed uses it for the cross-path lowpass and HF shelf; loudness uses it for both K-weighting stages. This is a good use of 2-lane NEON because the recurrence is serial in time but parallel across channels.

### P-04 — AutoMix tone is already NEON for the main stereo case

The stereo tone path is handled by `nar_automix_tone_process_stereo_neon()` before the scalar fallback (`automix_tone_processor.c:381-389`). Only the optional true-peak post-pass remains scalar.

### P-05 — Fail-open and real-time discipline are visible in the code

- Processors sanitize non-finite samples in place and fail open rather than aborting a buffer.
- Control knobs use atomics; the live tracker uses a seqlock-style publication protocol and a non-blocking audio-side writer.
- Bypass paths return early without touching audio.
- The biquad state layout used by the NEON kernel is documented and statically asserted in the tone processor.

### P-06 — Existing tests cover more than happy paths

The native C tests cover RMS, vocal/center-channel behavior, structural cues, planner behavior, chord vocabulary, energy quarters, tempo curve, and scalar/NEON tone parity. The AutoMix Dart tests cover the 32-value ABI, unknown-value semantics, and planner determinism.

The gap is specifically **performance/stage parity for the analyzer**, not a total absence of tests.

### P-07 — JNI and buffer boundaries have defensive checks

`automix_jni.cpp` checks null arrays, sample count, sample rate, chord capacity, and result size. `native_dsp_jni.c` checks buffer capacity before processing. The downsampler excludes LFE and handles anti-phase stereo instead of blindly averaging to silence.

### P-08 — Build split is deliberate

The host/Dart FFI library and the Android JNI libraries are separated. Android-only `native_dsp_jni.c` is guarded in the native-assets hook, and phase lock lives in the Android CMake library. This is not accidental duplication.

---

## 5. Findings

Severity here means **optimization importance**, not security severity. No exploitable defect or correctness failure was confirmed.

### F-01 — Main AutoMix magnitude/feature loop is source-level scalar

- **Severity:** High (offline performance opportunity)
- **File/line:** `native_audio_runtime/src/automix_analyzer.c:759-825`
- **Description:** For each STFT frame, the code calls the NEON window/RMS kernel, then runs a scalar FFT, then loops over 1,024 bins computing `sqrtf`, `logf`, total/vocal-band magnitudes, spectral flux, centroid inputs, and HPCP inputs. The cepstrum path also performs 1,024 `logf` calls on every other active frame (`:119-186`).
- **Root cause:** The loop was written for clarity and numerical control. `logf` is a libm call that inhibits vectorization; the vocal-band and chroma tests are data-dependent branches; the accumulators are mostly `double` to preserve analysis stability.
- **Impact:** Background AutoMix analysis wall time per 300 s window; not the audio callback. At 300 s this is ~12,916 frames × 1,024 bins ≈ **13.2 million** `sqrtf`/`logf` evaluations, plus ~6.6 million cepstrum `logf` evaluations in the worst case.
- **Confidence:** High that the source is scalar and branchy. Low-to-medium that explicit NEON will produce a material end-to-end win, because the FFT and `logf` costs remain.
- **Recommendation:** If profiling shows this pass matters, vectorize the deterministic parts first:
  - four bins at a time: real/imaginary load, `vmlaq_f32` for `re² + im²`, `vsqrtq_f32`, vector band sums/masks;
  - vector positive spectral flux (`vsubq`, `vmaxq`, accumulate);
  - keep `logf` scalar in phase 1, or use a validated vector `log2` approximation only after error analysis;
  - preserve double accumulators or document and test the changed summation order.
- **Risk:** Output drift in BPM/key/vocal/structure features; changes in band boundaries; NaN/Inf behavior; loss of bit-exactness; AutoMix cache invalidation. Do not introduce a fast log approximation without tests against the existing analyzer corpus.

### F-02 — Shared radix-2 FFT is scalar and dominates the static operation count

- **Severity:** High (offline performance opportunity)
- **File/line:** `native_audio_runtime/src/automix_analyzer.c:78-117`
- **Description:** `radix2_fft()` does a scalar bit-reversal permutation, then 11 stages of scalar butterflies with `twiddle = k * stride` loads. It is called by the main STFT (`:781`), the cepstrum (`:141`), and every chord-analysis frame (`:1396`).
- **Root cause:** A compact, allocation-free scalar FFT was sufficient for offline analysis. The butterfly inner loop is not written with NEON intrinsics, and the twiddle access is strided in early stages.
- **Impact:** At 300 s the main analyzer performs about 19,374 FFTs (12,916 STFT + 6,458 cepstrum), and the chord pass adds about 12,558 FFTs, for roughly **31,900 FFTs**. That is ~360 million complex butterflies. At 900 s the estimate is ~95,900 FFTs and ~1.08 billion butterflies. These are static counts, not measured time.
- **Confidence:** High that the source is scalar. Medium that NEON will reduce wall time substantially; the compiler may auto-vectorize some late-stage contiguous butterflies, and FFT performance may be limited by memory/twiddle access rather than arithmetic.
- **Recommendation:** Treat FFT vectorization as the first candidate **only after** stage timing or disassembly shows it dominates:
  - keep bit reversal scalar;
  - precompute stage-specific, contiguous twiddle tables so each vector load is sequential;
  - vectorize four `k` lanes for stages with `half >= 4`, with scalar tails;
  - reuse the same kernel for main, cepstrum, and chord FFTs;
  - preserve the scalar reference implementation behind a test/build switch.
- **Risk:** High implementation complexity; floating-point reassociation and phase drift; code size/I-cache pressure; twiddle-table memory overhead; compiler contraction differences. A vectorized FFT that is numerically different can flip tempo or chord decisions even if it is “close.”

### F-03 — Chord pass adds a separate scalar FFT/magnitude workload

- **Severity:** Medium (offline performance opportunity)
- **File/line:** `native_audio_runtime/src/automix_analyzer.c:1285-1458`
- **Description:** The chord pass uses 2 s windows with a 1 s hop. Each window runs 42 overlapping 2,048-point FFTs (1,024-sample hop), then computes `hypot()` in double precision for every bin and folds magnitudes through the branchy `hpcp_add_frame()`.
- **Root cause:** Chord analysis was implemented as a separate, robust pass. It reuses the scalar FFT but uses `hypot()` rather than `sqrtf()`, and has its own HPCP/chord scoring.
- **Impact:** At 300 s there are 299 windows × 42 FFTs ≈ **12,558 FFTs** and ≈ **12.9 million double `hypot()` calls**; at 900 s, 899 × 42 ≈ 37,758 FFTs and ≈ 38.7 million `hypot()` calls. This is not a rounding error next to the main analyzer.
- **Confidence:** High on the static counts. Medium on the benefit of replacing `hypot()` with a cheaper form, because chord confidence/boundary behavior is sensitive to numerical changes.
- **Recommendation:** Measure chord-pass time separately. If it is material:
  - reuse the optimized shared FFT;
  - evaluate `sqrt(x*x + y*y)` in double or float for finite FFT outputs instead of `hypot()`, with explicit range/NaN tests;
  - vectorize the magnitude/sqrt loop, but leave HPCP peak folding scalar until its branch behavior is understood.
- **Risk:** Chord-root/quality flips; cache invalidation; double-to-float accuracy loss; `hypot()`’s overflow/underflow scaling is unnecessary for this bounded input but must be proven.

### F-04 — Acoustic Engine has five scalar biquads per channel

- **Severity:** Medium-low (conditional, effect-dependent)
- **File/line:** `native_audio_runtime/src/acoustic_engine_processor.c:142-218`
- **Description:** Each frame runs `sub_hp`, `bass_lp`, `harmonic_hp`, `presence`, and `harsh_bp` biquads per channel, plus a memoryless `x*abs(x)` harmonic and a linked envelope. The effect is disabled by default (`lib/services/media_capabilities_service/service.dart:46`) and only runs when the user enables it.
- **Root cause:** The five-stage cascade has serial dependencies within each channel; the code uses the scalar `nar_biquad_process_sample()` helper for each stage.
- **Impact:** At 48 kHz stereo, roughly 480,000 biquad-sample updates per second when enabled, plus waveshaper/envelope work. This is not a primary playback bottleneck, but it is measurable when the effect is on.
- **Confidence:** High on the scalar structure. Low on the practical benefit, because the effect is optional and the five stages are serially dependent.
- **Recommendation:** Only if an effect-on profile shows a meaningful share: use the existing `nar_biquad_stereo_neon()` for each of the five stages, processing L/R in parallel. Do not attempt to vectorize across cascaded stages; the state dependency prevents it.
- **Risk:** State/coefficient layout must match the assembly kernel; NaN fail-open behavior must be preserved; audible differences from different rounding; effect-on tests are required.

### F-05 — AutoMix true-peak limiter is scalar, but only during overlaps

- **Severity:** Low
- **File/line:** `native_audio_runtime/src/automix_tone_processor.c:262-354`, call at `:434-462`
- **Description:** `true_peak_frame()` evaluates three 4-tap Lagrange interpolation sets per channel, then `apply_true_peak_limiter()` maintains a serial gain/release state and clamps the output. The stereo tone path is NEON, but this post-pass is scalar.
- **Root cause:** The limiter is a safety stage with sequential gain state; the 4-tap interpolation is small and branch-light but not written with intrinsics.
- **Impact:** During AutoMix overlap only; at 48 kHz stereo, about 1.15 million 4-tap evaluations per second. Small relative to the rest of the tone path.
- **Confidence:** High on the static cost. Low on benefit.
- **Recommendation:** Leave scalar unless overlap profiling says otherwise. If changed, vectorize across the two channels (or use a 4-lane dot product per channel) while keeping the serial gain state scalar.
- **Risk:** True-peak ceiling behavior, release timing, and per-deck L1 fade assumptions are safety-sensitive. A rounding change could alter the ceiling.

### F-06 — JNI may copy the 300 s float array twice

- **Severity:** Low (non-SIMD boundary)
- **File/line:** `android/app/src/main/cpp/replaygain/automix_jni.cpp:8-33`, `:73-111`
- **Description:** Both native analysis entry points call `GetFloatArrayElements()`. ART may return a direct pointer or a copy depending on the array/GC state. At 300 s × 22,050 Hz × 4 bytes, one copy is ~25.2 MiB; two passes can copy ~50.4 MiB. The Kotlin side correctly reuses one `monoPcm` array, so the JVM allocation is avoided, but JNI copies may remain.
- **Root cause:** Java arrays are not guaranteed pinned; `GetFloatArrayElements` is the portable access path.
- **Impact:** Memory bandwidth and analysis latency, not SIMD throughput. This is not a NEON candidate.
- **Confidence:** Medium: the potential copy is confirmed; whether ART actually copies in this workload must be measured (`is_copy` is available in the first helper and currently unused for decisions).
- **Recommendation:** Measure `is_copy` and end-to-end analysis time. If copies dominate, consider a combined native entry point that analyzes features and chords in one JNI call, or a direct `FloatBuffer`/`ByteBuffer` path. Do not use `GetPrimitiveArrayCritical` casually; it can block GC and lengthen critical sections.
- **Risk:** JNI/GC interaction, larger API surface, platform-specific behavior.

### F-07 — Kotlin downsampler is a non-SIMD boundary, possibly material

- **Severity:** Low-medium (out of native scope, but relevant to end-to-end latency)
- **File/line:** `android/app/src/main/kotlin/dev/wndavenz/music/automix/AutomixPcmDownsampler.kt:78-160`
- **Description:** Every source PCM frame runs a Kotlin `processFrame()` with channel selection, center/side power accumulation, a double-precision Butterworth low-pass, and decimation. At 44.1 kHz for 300 s, that is ~13.2 million source frames before producing 22.05 kHz output.
- **Root cause:** The downsampler prioritizes correctness and anti-phase/LFE handling over native throughput.
- **Impact:** It may be a significant share of end-to-end AutoMix analysis time, but it is not C and cannot be fixed by ARM NEON intrinsics in the native library.
- **Confidence:** High on the per-frame structure; unknown share of total time.
- **Recommendation:** Profile the Kotlin decode+downsample stage before touching the analyzer. If it dominates, move the kernel to native C/NEON or batch it; do not add NEON to unrelated DSP as a proxy.
- **Risk:** Changing channel/LFE/anti-phase behavior changes analysis inputs and therefore every downstream feature.

### F-08 — No stage-level analyzer benchmark or direct FFT/magnitude parity test

- **Severity:** Medium (validation/process gap)
- **File/line:** `native_audio_runtime/test/native_benchmark.dart:1-130`; `native_audio_runtime/test/automix_native_c_test.c`
- **Description:** The only native benchmark measures `NativeDspPipeline.processBuffer()` throughput. It does not time `nar_automix_analyze_centered`, `nar_automix_analyze_chords`, FFT stages, magnitude loops, the JNI copy, or the Kotlin downsampler. Existing functional tests check analyzer outputs and tone NEON parity, but there is no direct scalar-vs-NEON parity test for the FFT/magnitude path because no vectorized version exists yet.
- **Root cause:** The benchmark was written for the real-time pipeline; AutoMix analysis is newer and offline, so it was not included.
- **Impact:** Any optimization would be speculative. It would also be easy to “improve” a microbenchmark while regressing end-to-end analysis.
- **Confidence:** High.
- **Recommendation:** Before implementing F-01/F-02/F-03, add:
  - a C benchmark that times main analysis, chord analysis, and (if possible) FFT/magnitude stages separately;
  - a Dart/Kotlin end-to-end timing path;
  - a scalar-reference switch for direct output comparison;
  - a generated-assembly check for the candidate loops.
- **Risk:** Benchmark contamination (cache, thermal, CPU frequency), overfitting to synthetic tracks, and measuring a stage that is not the real bottleneck.

### F-09 — Optimization flags are not explicit or identical across native libraries

- **Severity:** Info (build/reproducibility)
- **File/line:** `native_audio_runtime/hook/build.dart`; `android/app/src/main/cpp/CMakeLists.txt:91`, `:167`; `.agents/memory/native-runtime-internals.md:20`
- **Description:** The native-assets hook does not set `-O3` or `-march=armv8-a+simd`. The ReplayGain CMake target sets only `-Wall -Wextra -fvisibility=hidden`; only Stretch gets `-O3`. Repo memory says the native runtime uses `-O3` and `-march=armv8-a+simd`, but that is not visible in the current hook/CMake files.
- **Root cause:** Flags may come from toolchain defaults or an earlier build configuration; the repo does not record the final compile command.
- **Impact:** The two libraries that compile `automix_analyzer.c` may use different optimization levels, and benchmark results may not be comparable. NEON code generation and auto-vectorization also depend on these flags.
- **Confidence:** High on the file contents; unknown on the effective flags.
- **Recommendation:** Capture `compile_commands.json` or a verbose native build log. Ensure the benchmark and both production libraries use the intended `-O3`/architecture flags. Do not add `-ffast-math` to the analyzer without a parity plan; it can change NaN/Inf and reassociation behavior.
- **Risk:** Benchmarking a configuration that does not match the shipped APK.

---

## 6. Do-not-convert register

These are concrete reasons not to vectorize, not claims that the code is optimal.

| ID | Area | File/line | Reason | Confidence |
|---|---|---|---|---|
| D-01 | Live AutoMix tracker | `automix_live_tracker.c:517-631` | Per-sample work is small; autocorrelation runs every 25 frames (250 ms) over a bounded 600-frame ring in FP64. Estimated ~100k MAC per estimate, ~4 estimates/s. Real-time risk outweighs benefit. | High |
| D-02 | Compressor | `comp_processor.c:209-250` | Serial envelope and one `logf` + one `expf` per frame; no vector log/exp; gain application is already a two-channel unroll. | High |
| D-03 | Limiter | `limiter_processor.c:159-240` | Serial look-ahead delay/gain state; rare division; stereo path already unrolled. | High |
| D-04 | Soft clipper | `soft_clipper_processor.c:119-140` | Branch is strongly biased to transparent pass-through; `tanh` only on rare clips; compiler handles the linear path. | High |
| D-05 | HPCP peak folding | `automix_analyzer.c:278-323` | Data-dependent peak detection and harmonic folding; branchy, not a straight-line arithmetic loop. | High |
| D-06 | AutoMix planner | `automix_planner.c:974-1060` | Combinatorial scalar search, qsort, doubles; no regular per-sample data layout. | High |
| D-07 | Gain / ReplayGain | `gain_processor.c:108`; `replaygain_processor.c:136` | Already uses the 16-sample NEON gain kernel. | High |
| D-08 | Crossfeed / loudness | `crossfeed_processor.c:239-246`; `loudness_processor.c:454-463` | Already uses the 2-lane NEON biquad kernel at the intended sites. | High |
| D-09 | AutoMix stereo tone | `automix_tone_processor.c:381-389` | Already uses the NEON stereo tone kernel. | High |
| D-10 | Pipeline / buffer | `dsp_pipeline.c`; `audio_buffer.c` | Pointer/stride and orchestration logic; no arithmetic hot loop. | High |
| D-11 | Stereo matrix | `stereo_matrix.h` | Small 2×2 matrix; compiler auto-vectorizes it; manual NEON would add overhead. | High |
| D-12 | External libraries | libebur128, TagLib, Signalsmith Stretch | Upstream code; out of scope and not owned by this audit. | High |

**Also preserve, do not replace:**

- `nar_automix_window_rms_neon()`: already covers the analyzer’s window/RMS stage.
- `nar_gain_apply_neon()`: already 16 samples/iteration.
- `nar_biquad_stereo_neon()`: already the right two-channel biquad form.

---

## 7. Priority matrix

| Priority | Candidate | Static leverage | Confidence in benefit | Gate before work |
|---|---|---|---|---|
| **P0** | Analyzer stage benchmark + compile flags/assembly audit | Prerequisite | High | Must be done first |
| **P1** | Shared `radix2_fft()` (main + cepstrum + chords) | ~31.9k FFTs/300 s; ~360M butterflies | Medium | Stage timing shows FFT dominant |
| **P2** | Main magnitude/feature loop | ~13.2M `sqrtf`/`logf` + 13.2M HPCP bins | Low-medium | Stage timing; log strategy |
| **P3** | Chord magnitude/`hypot` loop | ~12.6k FFTs + 12.9M double `hypot` | Medium | Chord pass is material |
| **P4** | Acoustic Engine stereo biquads | 5 biquads × 2 channels when enabled | Low | Effect-on profile |
| **P5** | True-peak limiter | 3 × 4-tap × 2 channels during overlap | Low | Overlap profile |
| **P6** | JNI copy / Kotlin downsampler | ~50 MiB copies; ~13.2M Kotlin frames | Medium/unknown | End-to-end timing |
| **Never** | Live tracker, compressor, limiter, soft clip, planner, pipeline, existing NEON | Small/serial/branchy/already done | — | — |

Static leverage is not a substitute for timing. P1 and P2 could swap after profiling; the shared FFT is ranked first only because it is used by three passes and has the largest arithmetic count.

---

## 8. Recommended implementation order

### Gate 0 — Measure first

1. Build a baseline with the intended release flags on the target device or an equivalent arm64 Android device.
2. Time, separately:
   - Kotlin decode + downsampler;
   - JNI feature analysis;
   - JNI chord analysis;
   - main analyzer FFT vs magnitude vs HPCP/feature stages (compile-time profiling switch or C benchmark).
3. Capture generated assembly for `radix2_fft`, the magnitude loop, and the biquad kernels.
4. Record `simpleperf`/Perfetto counters and thermal state.

If this gate cannot be completed, stop. The audit does not justify speculative code changes.

### Gate 1 — Choose the first target

- If FFT dominates: implement **F-02** first.
- If the main magnitude/feature loop dominates: implement **F-01** first.
- If the chord pass is a large share: schedule **F-03** immediately after the shared FFT.
- If Kotlin/JNI dominates: fix the boundary before touching C.

### Step 2 — Implement with a scalar reference

For the chosen kernel:

1. Keep the current implementation as the reference path.
2. Add a compile-time or test-only scalar switch.
3. Add NEON C intrinsics with a scalar tail.
4. Preserve input/output contracts and failure behavior.
5. Run parity tests before performance tests.

### Step 3 — Expand only after wins

- Shared FFT first, then main magnitude/feature, then chord magnitude.
- Acoustic Engine and true-peak limiter only if their effect-on/overlap profiles justify the work.
- JNI/downsampler only as a non-SIMD follow-up.

### Stop conditions

- Less than an agreed material improvement (suggested: **10% end-to-end analyzer wall time** for a high-complexity FFT change; **5%** for a low-risk magnitude change).
- Any unresolved output drift that changes BPM/key/chord decisions.
- Code-size/I-cache cost that erases the gain.
- Inability to maintain a tested scalar fallback.

---

## 9. Testing and benchmark plan

### 9.1 Correctness

Add a scalar-vs-NEON parity harness around the analyzer. Suggested inputs:

| Input class | Purpose |
|---|---|
| 1 s, 2 s, 10 s, 30 s, 300 s, 900 s windows | Frame-count boundaries, cepstrum parity, chord pass, max window |
| 16 k, 22.05 k, 24 k, 44.1 k, 48 k sample rates | Analyzer rate handling (production is 22.05 k after downsampling) |
| Silence, DC, impulse, white noise, sine, sweep, click track | NaN/Inf, RMS floor, FFT, onset, tempo |
| Major/minor triads, sevenths, sus chords, detuned material | HPCP/chord behavior |
| Real music excerpts with known BPM/key | End-to-end sanity |
| Buffers offset by 1–4 floats | Unaligned vector loads/tails |
| Frame counts not divisible by 4/8/16 | Scalar tail correctness |

Comparison rules:

- Prefer bit-exact output for kernels that preserve operation order.
- For reassociated FFT/magnitude code, use ULP/relative-error bounds per stage, then assert downstream invariants:
  - finite 32-value ABI where required;
  - confidence in `[0,1]`;
  - no NaN/Inf in RMS/energy quarters;
  - tempo/key/chord decisions unchanged on non-borderline fixtures.
- Test `NAR_AUTOMIX_ANALYSIS_VALUE_COUNT` and chord row capacity exactly.
- Test NaN/Inf input behavior and silence floor.

If analyzer numeric behavior changes, decide explicitly whether to bump the AutoMix cache schema. Current schema is `_analysisSchemaVersion = 18` (`lib/services/automix_service/service.dart:1103`).

### 9.2 Performance

Measure both stages and end-to-end:

1. **C stage benchmark:** `clock_gettime(CLOCK_MONOTONIC)`, 5 warmups + 10 measured runs, report median and p95. Time main analysis, chord analysis, and FFT/magnitude sub-stages separately.
2. **Kotlin end-to-end:** `System.nanoTime()` around decode + downsample + JNI + result mapping.
3. **Android counters:** `simpleperf stat` or Perfetto for cycles/instructions/cache misses; record CPU frequency and thermal state.
4. **Worst case:** 300 s and, if callers use it, 900 s windows.
5. **No emulator-only conclusion:** the target is Cortex-A76/A55; scheduler and memory behavior differ from x86 host or emulator.
6. **Audio-thread check:** for any real-time change, use `dumpsys media.audio_flinger`/Perfetto to confirm no xrun or callback overrun. The AutoMix analyzer itself should remain off the audio thread.

### 9.3 Commands

Existing commands to run in a capable environment:

```bash
flutter pub get
dart analyze lib test
flutter test

cd native_audio_runtime
dart test
dart test test/native_benchmark.dart -r expanded

cd ../android
./gradlew :app:testDebugUnitTest
```

The native Dart tests currently need an Android-compatible loader for `__android_log_print`; do not treat the Termux failure as a product failure. Use the Android build/CI toolchain for the real native verification.

### 9.4 Acceptance

- Functional parity: all existing tests pass, plus the new scalar/NEON parity suite.
- Output stability: no unexplained BPM/key/chord changes on the corpus.
- Performance: measurable end-to-end improvement under the agreed threshold.
- Safety: no new NaN/Inf path, no audio-thread allocation/logging, no callback overrun.
- Maintainability: scalar fallback remains, and the NEON path is documented with its assumptions.

---

## 10. Risks and mitigations

| Risk | Why it matters | Mitigation |
|---|---|---|
| Numerical drift changes AutoMix decisions | BPM/key/chord/phase are discrete outputs; a tiny FFT change can flip a bin | Parity corpus, tolerance bands, downstream invariants, cache version decision |
| `logf` remains scalar | Limits magnitude-loop speedup | Measure first; keep scalar log or validate a vector approximation separately |
| Compiler already auto-vectorizes parts | Manual NEON may add complexity for little gain | Inspect generated assembly; benchmark before/after |
| FFT vectorization complexity | High bug surface, twiddle layout, tails, rounding | Shared scalar reference; stage-by-stage tests; code review |
| `hypot` replacement changes chord confidence | Chord boundaries can flip | Dedicated chord tests; compare quality IDs and confidence distributions |
| JNI critical section/GC risk | A “fast” copy fix can introduce stalls | Measure `is_copy`; prefer combined JNI call or direct buffer over critical sections |
| Benchmark contamination | Thermal/frequency/cache effects can reverse conclusions | Warmups, repeated medians, same device/flags, record thermal state |
| Build flag mismatch | Benchmarking a different binary than shipped | Capture compile commands; verify both native libraries |
| Inconsistent NEON/assembly maintenance | Existing `.S` kernels and new intrinsics can diverge | Keep one reference per kernel; document call sites; parity tests |

---

## 11. Unresolved questions

1. What is the actual stage split inside `nar_automix_analyze_centered` on the target device: FFT, magnitude/log, HPCP, tempo, or chord?
2. Does Clang already auto-vectorize the magnitude sums or late-stage FFT butterflies in the shipped library?
3. Does ART copy the 300 s `float[]` in `GetFloatArrayElements` for this workload (`is_copy`)?
4. How much end-to-end analysis time is spent in the Kotlin decoder/downsampler versus native code?
5. What optimization flags are actually used for `libnative_audio_runtime.so` and `libreplaygain_native.so`?
6. Are 900 s analysis windows used in production, or is 300 s the effective cap?
7. How sensitive are BPM/key/chord decisions to small floating-point differences on real tracks?
8. Is the Acoustic Engine enabled often enough to justify its five-biquad optimization?
9. Is the true-peak limiter active during all AutoMix overlaps, or only some user configurations?
10. What improvement threshold is required to accept added FFT complexity and maintenance cost?

---

## Appendix A — Static work estimates

These are arithmetic counts from the code, not measured timings. “Worst case” assumes every cepstrum frame is active; silence gates some cepstrum work at runtime.

| Quantity | 300 s @ 22.05 kHz | 900 s @ 22.05 kHz |
|---|---:|---:|
| Input samples | 6,615,000 | 19,845,000 |
| Main STFT frames | 12,916 | 38,756 |
| Main STFT FFTs | 12,916 | 38,756 |
| Cepstrum FFTs (every other active frame) | 6,458 | 19,378 |
| Main total FFTs | 19,374 | 58,134 |
| Main magnitude/log bins | 13,225,984 | 39,686,144 |
| Cepstrum log bins | 6,612,992 | 19,843,072 |
| Chord windows (2 s / 1 s hop) | 299 | 899 |
| Chord FFTs (42/window) | 12,558 | 37,758 |
| Chord magnitude (`hypot`) bins | 12,859,392 | 38,664,192 |
| Total FFTs | 31,932 | 95,892 |
| Total magnitude evaluations | 26,085,376 | 78,350,336 |
| Complex butterflies (approx.) | 359,682,048 | 1,080,127,488 |
| JNI float bytes per pass (if copied) | 26,460,000 | 79,380,000 |

The table is a worst-case arithmetic model. The cepstrum is gated by the RMS floor and every-other-frame sampling; silence reduces the actual count. The 900 s column is included because the bridge accepts up to 900 s, while 300 s is the default (`MAX_ANALYZE_SECONDS = 300`).

---

## Appendix B — Key source references

| Topic | File:line |
|---|---|
| Analyzer constants | `native_audio_runtime/src/automix_analyzer.c:7-38` |
| FFT | `native_audio_runtime/src/automix_analyzer.c:78-117` |
| Cepstrum | `native_audio_runtime/src/automix_analyzer.c:119-186` |
| HPCP | `native_audio_runtime/src/automix_analyzer.c:278-323` |
| Main frame loop | `native_audio_runtime/src/automix_analyzer.c:759-825` |
| Chord pass | `native_audio_runtime/src/automix_analyzer.c:1285-1458` |
| AutoMix window/RMS NEON call | `native_audio_runtime/src/automix_analyzer.c:763` |
| Live tracker process | `native_audio_runtime/src/automix_live_tracker.c:517-631` |
| Live tracker update guard | `native_audio_runtime/src/automix_live_tracker.c:594-597` |
| Tone stereo NEON call | `native_audio_runtime/src/automix_tone_processor.c:381-389` |
| True-peak limiter | `native_audio_runtime/src/automix_tone_processor.c:262-354`, `:434-462` |
| Acoustic Engine | `native_audio_runtime/src/acoustic_engine_processor.c:142-218` |
| Crossfeed NEON calls | `native_audio_runtime/src/crossfeed_processor.c:239-246` |
| Loudness NEON K-weight | `native_audio_runtime/src/loudness_processor.c:450-463`, call `:523` |
| Gain NEON call | `native_audio_runtime/src/gain_processor.c:108` |
| ReplayGain NEON call | `native_audio_runtime/src/replaygain_processor.c:136` |
| Compressor serial loop | `native_audio_runtime/src/comp_processor.c:209-250` |
| Limiter serial loop | `native_audio_runtime/src/limiter_processor.c:159-240` |
| Soft clipper loop | `native_audio_runtime/src/soft_clipper_processor.c:119-140` |
| Planner search | `native_audio_runtime/src/automix_planner.c:974-1060` |
| AutoMix JNI | `android/app/src/main/cpp/replaygain/automix_jni.cpp:8-111` |
| Analysis bridge constants | `android/app/src/main/kotlin/dev/wndavenz/music/automix/AutomixAnalysisBridge.kt:37-40` |
| Analysis bridge JNI calls | `android/app/src/main/kotlin/dev/wndavenz/music/automix/AutomixAnalysisBridge.kt:142-161` |
| Kotlin downsampler | `android/app/src/main/kotlin/dev/wndavenz/music/automix/AutomixPcmDownsampler.kt:78-160` |
| Native-assets sources | `native_audio_runtime/hook/build.dart:53-83` |
| Android CMake | `android/app/src/main/cpp/CMakeLists.txt:62-91`, `:160-170` |
| ABI/SDK | `android/app/build.gradle:50-51`, `:79-85`, `:103` |
| Cache schema | `lib/services/automix_service/service.dart:1103` |

---

## Appendix C — Audit conclusion

- **Real-time NEON work:** not justified by the current evidence.
- **Offline AutoMix work:** the only defensible optimization program.
- **First target:** shared FFT and/or main magnitude/feature loop, selected by measurement.
- **Second target:** chord pass, because it is larger than it first appears.
- **Conditional targets:** Acoustic Engine and true-peak limiter, only with effect/overlap profiling.
- **Not NEON:** JNI copies and the Kotlin downsampler; these are end-to-end latency questions.
- **Required before implementation:** a stage benchmark, generated-assembly inspection, actual compile flags, and a scalar-reference parity harness.

No code was modified by this audit.
