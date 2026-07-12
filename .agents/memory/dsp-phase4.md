---
name: Phase 4 DSP Core
description: Native DSP pipeline architecture (dsp_pipeline.c, gain_processor.c, NativeDspPipeline Dart facade); wiring and threading notes.
---

# Phase 4 Native DSP Core

## Rule
Any new native DSP processor must implement `NarDspProcessorVTable` in a `.c` file and call `nar_dsp_pipeline_register_internal()` from its own init. Never modify `dsp_pipeline.c` to add a processor — just create a new `.c` file and add it to `hook/build.dart` sources list.

**Why:** The pipeline's `register_internal()` is the only extension point; processor code is isolated per file (matching the header-per-file contract).

## How to apply
- New processor: create `src/<name>_processor.h/c`, implement all 5 vtable functions, register with `nar_dsp_pipeline_register_internal()`.
- Add `.c` to `hook/build.dart` `sources` list.
- Add Dart knob getters/setters to `NativeDspPipeline` in `dsp_pipeline_io.dart`.
- Mirror stubs in `dsp_pipeline_unsupported.dart`.
- Expose controls via `PlaybackManager` (never expose `NativeDspPipeline` directly to UI).

## Atomic float trick
Gain uses `_Atomic int32_t` + `memcpy` for float bits — guaranteed lock-free on all ABIs. Do NOT use `_Atomic float` directly (not guaranteed lock-free everywhere).

## Threading contract
- `nar_dsp_pipeline_process()` / `reset()` → single audio thread only
- `set_enabled()` / gain knobs → any thread (atomics)
- `register_internal()` / `dispose()` → mutex-guarded, not audio-thread-safe

## Pipeline NOT wired to Media3 yet
Phase 4 pipeline exists but `nar_dsp_pipeline_process()` is NOT called by ExoPlayer audio thread. Phase 5+ must implement ExoPlayer `AudioProcessor` interface to call it per output buffer.

## analysis_options.yaml exclude
Workspace root `analysis_options.yaml` excludes `native_audio_runtime/test/**` because `package:test` is a dev-dependency of the sub-package, not the workspace. Run `dart test` from inside `native_audio_runtime/` to exercise those files.
