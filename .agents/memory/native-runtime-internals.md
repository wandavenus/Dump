---
name: Native Audio Runtime Internals
description: build.dart hook, Dart FFI bindings, DSP pipeline C internals, JNI functions, dynamics_common structs.
---

# Native Audio Runtime — Internals

## Package Info

- `native_audio_runtime/pubspec.yaml`: local FFI package; no external Dart deps beyond `ffi`
- Dart FFI package template + native-assets hooks
- `dart.library.ffi` web-stub trick for web compatibility

## hook/build.dart — Build Hook Logic

Dart native-assets hook — compiles C sources and links shared library:
- **Platform condition**: Android arm64-v8a only (matches app `abiFilters`)
- **Compiler**: requires `clang` on PATH (`native_toolchain_c` convention); on dev: `ln -sf $(which gcc) /tmp/clang`
- **Sources compiled**: all `.c` files in `src/` (excluding `native_dsp_jni.c` which is Android-only and handled via CMake separately)
- **Flags**: `-O3`, `-march=armv8-a+simd` (enables NEON), `-ffast-math` (on non-audio-path files)

## lib/ — Dart FFI Bindings

Dart-side FFI wrappers that call into the C library:

| Dart class | C function(s) | Role |
|------------|--------------|------|
| `NativeAudioRuntime` | `nar_*` lifecycle | Singleton; `initialize()`, `dispose()` |
| `NarDspPipeline` | `nar_dsp_pipeline_*` | Pipeline create/destroy/process |
| `NarAudioBufferRef` | `nar_audio_buffer_*` | Buffer lifecycle and access |
| Processor wrappers | `nar_*_set_params`, `nar_*_set_bypass` | Per-processor param setters |
| `NarAaudioProbe` | `nar_aaudio_probe_*` | AAudio latency probe results |

`NativeDspBridge.dart` calls `NativeAudioRuntime` FFI singleton on `initialize()`.

## DSP Pipeline C Internals (`dsp_pipeline.c/.h`)

```c
typedef struct NarProcessorDesc {
  const char* id;
  NarProcessFn  process;    // (buf, stream_count, sample_rate) → void
  NarBypassGetFn get_bypass;
  void* state;
} NarProcessorDesc;
```

`nar_dsp_pipeline_process(pipeline, buf)`:
1. For each registered `NarProcessorDesc` in order
2. Check `get_bypass(state)` → skip if bypassed
3. Call `process(buf, stream_count, sample_rate)`
4. Continue to next processor

Total pipeline latency: **63 frames** (limiter look-ahead).

## NarAudioBuffer Layout (`audio_buffer_internal.h`)

```c
struct NarAudioBuffer {
  float*   data;           // interleaved float32: [ch0s0, ch1s0, ch0s1, ch1s1, ...]
  int32_t  frame_count;
  int32_t  channel_count;
  int32_t  sample_rate;
  int64_t  timestamp_us;
  // internal allocation metadata
};
```

Data layout: **interleaved float32**. Frame indexing: `data[frame * channel_count + channel]`.

## JNI Functions (`native_dsp_jni.c`)

Every function follows `Java_dev_wndavenz_music_NativeDsp_*` naming:

| JNI function | Action |
|-------------|--------|
| `init` | Creates DSP pipeline, registers all processors |
| `process` | Called per audio buffer from `NativeDspAudioProcessor.kt` |
| `setBypass` | Bypass on/off per processor ID string |
| `setCompressorParams` | Forwards to `nar_comp_set_params` |
| `setLimiterParams` | Forwards to `nar_limiter_set_params` |
| `setGainDb` | Forwards to `nar_gain_set_db` |
| `setReplayGain` | Forwards to `nar_replaygain_set_gain` |
| `setLoudnessTarget` | Forwards to loudness processor |
| `setCrossfeedParams` | Forwards to `nar_crossfeed_set_params` |
| `destroy` | Frees pipeline |

## dynamics_common.h

```c
typedef struct NarEnvelopeDetector {
  float value_db;        // current smoothed level in dB (log domain)
  float coeff_attack;    // pre-computed from attack_ms + sample_rate
  float coeff_release;   // pre-computed from release_ms + sample_rate
} NarEnvelopeDetector;
```

Helpers: `nar_lin_to_db()`, `nar_db_to_lin()`, envelope update function.
`value_db` for log-domain level tracking — avoids per-sample `log()` calls.

## NEON Kernels (`neon_kernels.h` / `neon_kernels.S`)

| Kernel | Description |
|--------|-------------|
| `nar_gain_apply_neon` | 16 samples/iteration gain scalar multiply; ARM NEON `vld1q_f32` / `vmulq_f32` / `vst1q_f32` |
| `nar_biquad_stereo_neon` | 2-lane parallel L+R biquad processing; TDF-II with NEON intrinsics |

Both declared in `neon_kernels.h`, implemented in `neon_kernels.S` (ARM assembly).
