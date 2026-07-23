---
name: Native C DSP Layer Map
description: Every .c/.h file in native_audio_runtime/src/ with functions and role. DSP pipeline slot assignments.
---

# Native Audio Runtime — C Layer Map

## Package entry
- `native_audio_runtime/hook/build.dart` — Dart native-assets build hook
- `native_audio_runtime/src/native_dsp_jni.c` — JNI bindings; exposes DSP pipeline to Android Media3 layer

## Core Runtime & Buffer

| File | Key symbols | Role |
|------|-------------|------|
| `native_audio_runtime.h/.c` | `NarAudioBuffer` (opaque), versioning | Main entry point + lifecycle |
| `native_audio_runtime_internal.h` | internal shared defs | Internal types |
| `audio_buffer.h/.c` | `nar_audio_buffer_destroy`, `nar_audio_buffer_set_timestamp_us` | PCM buffer lifecycle API |
| `audio_buffer_internal.h` | `struct NarAudioBuffer` (interleaved float32/int16) | Full buffer layout |
| `dsp_pipeline.h/.c` | `NarProcessorDesc`, `nar_dsp_pipeline_process` | Ordered processor chain manager |
| `dsp_processor.h` | processor interface | DSP module interface definition |
| `dsp_stream.h` | multi-stream defs | Multi-stream DSP handling |

## DSP Processor Slots (ordered)

| Slot | Processor | File | Key symbols |
|------|-----------|------|-------------|
| 1 | ReplayGain | `replaygain_processor.h/.c` | `nar_replaygain_set_gain` |
| 2 | Loudness Norm | `loudness_processor.h/.c` | EBU R128 IIR real-time; 3s smoothing tau; abs gate −70 LUFS |
| 3 | Parametric EQ | *(removed — system EQ only)* | — |
| 3 | Crossfeed | `crossfeed_processor.h/.c` | `nar_crossfeed_set_params`; frequency-dependent; zero latency |
| 4 | Gain | `gain_processor.h/.c` | `nar_gain_set_db` |
| 5 | Compressor | `comp_processor.h/.c` | `nar_comp_set_params`, `NarCompState`; stereo fast-path at ch==2 |
| 6 | Limiter | `limiter_processor.h/.c` | `NarLimiterState`, `nar_limiter_set_params`; look-ahead 63 frames; stereo fast-path |
| 7 | Soft Clipper | `soft_clipper_processor.h/.c` | tanhf-based; no NEON opt (changes curve) |

**Default state:** compressor/limiter/soft_clipper/crossfeed native default bypass=0 (active) — Dart must force-bypass until user opts in.

## Utilities & Math

| File | Key symbols | Role |
|------|-------------|------|
| `dynamics_common.h` | `NarEnvelopeDetector`, dB/linear helpers | Shared dynamics math |
| `stereo_matrix.h` | `NarStereoMatrix` | 2×2 matrix ops for stereo width/panning; `static inline`, compiler auto-vectorizes |
| `neon_kernels.h` / `neon_kernels.S` | `nar_gain_apply_neon` (16 samples/iter), `nar_biquad_stereo_neon` (2-lane L+R) | ARM NEON SIMD; existing kernels |
| `biquad_filter.h/.c` | `NarBiquadCoeffs`, `NarBiquadState` | Biquad LP/HP/EQ implementation |
| `aaudio_probe.h/.c` | `nar_aaudio_probe_latency` | dlopen-based runtime AAudio ABI probe |

## Android CMake Targets (android/app/src/main/cpp/CMakeLists.txt)

| Target | Contents |
|--------|----------|
| `replaygain_native` | libebur128 (EBU R128 loudness) + TagLib (tag writing); M4A write unsupported by design |
| `stretch_native` | Signalsmith Stretch (STFT time-stretch/pitch-shift) + Signalsmith Linear (FFT) |

## Fail-open rule
Every native DSP call in PlaybackManager must fail-open — missing symbol or init failure must not crash; DSP simply bypasses.
