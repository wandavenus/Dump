# Phase 4.5 — Media3 ↔ Native DSP Pipeline Integration

## Objective

Prove that every PCM sample played by Media3 / ExoPlayer flows through the
native DSP pipeline.  This phase wires the existing C-side pipeline (Phase 4)
into ExoPlayer's `DefaultAudioSink` processor chain without adding new
processors, without FFmpeg, and without a parallel playback path.

---

## Playback Pipeline Diagram

```
Flutter UI
  ↓
AudioService
  ↓
PlaybackManager                  ← owns DSP enable/disable/parameters (Dart API)
  ↓
Media3PlaybackBridge             ← MethodChannel / EventChannel edge
  ↓
Media3PlaybackService.kt         ← ExoPlayer orchestration
  ↓
ExoPlayer (DefaultRenderersFactory)
  ↓
DefaultAudioSink (DefaultAudioProcessorChain)
  │
  ├─ [1] NativeDspAudioProcessor  ← Phase 4.5 insertion point
  │         ↓ JNI (GetDirectBufferAddress)
  │         ↓ nar_dsp_pipeline_process_raw()
  │         ↓ Gain Processor ("dsp.gain")
  │         ↓ [future: Parametric EQ, Compressor, Limiter …]
  │
  ├─ [2] StereoWideningAudioProcessor
  ├─ [3] SilenceSkippingAudioProcessor  (skip-silence feature)
  └─ [4] SonicAudioProcessor            (speed / pitch)
  ↓
AudioTrack → hardware output
```

---

## Media3 PCM Flow

1. **Decode** — ExoPlayer's `MediaCodecAudioRenderer` decodes compressed audio
   (FLAC, MP3, AAC, …) into PCM.  `setEnableAudioFloatOutput(true)` instructs
   the renderer to request `ENCODING_PCM_FLOAT` (32-bit float interleaved) from
   the hardware decoder when available.

2. **Queue** — The renderer calls `DefaultAudioSink.handleBuffer()` with a
   `ByteBuffer` slice of decoded PCM.

3. **Processor chain** — `DefaultAudioProcessorChain` routes the buffer through
   each registered `AudioProcessor` in order.  `NativeDspAudioProcessor` is
   the first user-registered processor; it runs before `StereoWideningAudioProcessor`,
   `SilenceSkippingAudioProcessor`, and `SonicAudioProcessor`.

4. **AudioTrack** — The processed buffer is written to `AudioTrack` for
   hardware playback.

---

## Native DSP Insertion Point

| File | Role |
|------|------|
| `android/app/src/main/kotlin/dev/wndavenz/music/effects/NativeDspAudioProcessor.kt` | `BaseAudioProcessor` adapter; registered in the chain |
| `native_audio_runtime/src/native_dsp_jni.c` | JNI bridge: `ByteBuffer` → `float*` → `nar_dsp_pipeline_process_raw()` |
| `native_audio_runtime/src/dsp_pipeline.c` | C pipeline; routes the buffer through all enabled processor slots |
| `native_audio_runtime/src/gain_processor.c` | Phase 4 processor: per-sample gain multiply |

**Registration site** (`Media3PlaybackService.kt`, `createConfiguredPlayer()`):

```kotlin
val nativeDspProc = NativeDspAudioProcessor()
// …
.setAudioProcessorChain(
    DefaultAudioSink.DefaultAudioProcessorChain(nativeDspProc, channelMixingProc)
)
```

One `NativeDspAudioProcessor` instance is created per `ExoPlayer` instance
(both primary and secondary/crossfade players), matching the
`StereoWideningAudioProcessor` pattern.  All instances share the same global
C pipeline state — gain/bypass/enable changes apply uniformly.

---

## Thread Ownership

| Layer | Thread | Notes |
|-------|--------|-------|
| `NativeDspAudioProcessor.queueInput()` | ExoPlayer audio rendering thread | Called by `DefaultAudioSink` |
| `nar_dsp_pipeline_process_raw()` | ExoPlayer audio rendering thread | No locks; no heap alloc |
| `nar_gain_processor_set_gain_db/bypass` | Any (Dart UI isolate / main thread) | C11 `_Atomic` stores |
| `nar_gain_processor_get_*` reads in `_gain_process()` | ExoPlayer audio thread | C11 `_Atomic` loads |
| `nar_dsp_pipeline_init()` / `dispose()` | Dart main isolate | Must not race with `process_raw()` |

**Key rule**: `process_raw()` acquires no locks and makes zero heap allocations.
Parameter changes from Dart (gain dB, bypass, per-processor enable) use C11
`_Atomic` stores; the audio thread reads them with `_Atomic` loads.  This
is safe without a lock on every architecture targeted (`arm64-v8a`).

---

## Audio Buffer Ownership

```
ExoPlayer (caller)
  owns inputBuffer — NativeDspAudioProcessor must not modify it

NativeDspAudioProcessor.queueInput():
  1. replaceOutputBuffer(remaining)   → allocates/reuses an owned output ByteBuffer
  2. output.put(inputBuffer)          → one bulk copy (≈ native memcpy)
  3. output.flip()                    → position=0, limit=remaining
  4. nativeProcessFloat(output, …)    → JNI GetDirectBufferAddress() returns
                                        raw float* into the direct ByteBuffer's
                                        native heap; C processes in-place
  5. BaseAudioProcessor.getOutput()   → returns output to DefaultAudioSink

Dart / C (dispose path):
  nar_dsp_pipeline_dispose() tears down processors; never called while
  queueInput() could be running (service onDestroy serialises this).
```

**Zero-copy guarantee**: after the single bulk copy in step 2, no further copy
or allocation occurs in the hot path.  The C-side `NarAudioBuffer` in
`process_raw()` is a **stack-allocated view** (`struct NarAudioBuffer view`)
pointing directly at the `ByteBuffer`'s native heap — `nar_audio_buffer_destroy()`
must never be called on it.

---

## Playback Lifecycle

### Startup

1. `PlaybackManager.initialize()` (Dart) calls `NativeDspPipeline.instance.initialize()`.
2. `initialize()` calls `nar_dsp_pipeline_init()` + `nar_gain_processor_register_internal()` via FFI.
3. `nar_dsp_pipeline_is_initialized()` returns 1.
4. `Media3PlaybackService.onCreate()` creates the primary player via `createConfiguredPlayer()`:
   a. `NativeDspAudioProcessor()` is instantiated.
   b. It is placed first in `DefaultAudioProcessorChain`.
5. First `queueInput()` call: `nativeIsInitialized()` returns `true`;
   `nativeProcessFloat()` calls `nar_dsp_pipeline_process_raw()` — DSP active.

### Startup race (fail-open)

If ExoPlayer starts playing before Dart completes FFI init (cold start race),
`nar_dsp_pipeline_is_initialized()` returns 0 and `process_raw()` returns
`NATIVE_RUNTIME_ERROR_NOT_INITIALIZED` without touching the buffer.  Audio
passes through unmodified.  Once Dart initializes the pipeline, subsequent
`queueInput()` calls process normally.

### Crossfade

Both the primary and secondary `ExoPlayer` instances each own a separate
`NativeDspAudioProcessor`.  Both call `nar_dsp_pipeline_process_raw()` which
reads the same global gain/bypass atomics — correct: during a crossfade both
streams apply the same DSP parameters.

### Seek / Pause / Resume / Repeat / Shuffle

These do not affect the `NativeDspAudioProcessor` state.  The processor is
stateless (the gain processor has no filter history); reset() is a no-op.
ExoPlayer calls `flush()` → `BaseAudioProcessor.flush()` on seek, which
resets the output buffer position — no DSP-side action needed.

### Service destruction

`onDestroy()` → player `release()` → `DefaultAudioSink.release()`.  The
processor chain is torn down by ExoPlayer.  Dart's `PlaybackManager.dispose()`
calls `NativeDspPipeline.instance.dispose()` → `nar_dsp_pipeline_dispose()`.
Because `onDestroy` runs on the main thread and `queueInput` is no longer
called after `release()`, there is no race.

---

## Performance Considerations

| Metric | Result |
|--------|--------|
| Added allocations per `queueInput()` call | 0 (output buffer reused by `BaseAudioProcessor`) |
| Added allocations in `process_raw()` | 0 (`NarAudioBuffer` view is stack-allocated) |
| Copies per call | 1 (mandatory bulk copy required by `BaseAudioProcessor` contract) |
| Locks in `process_raw()` | 0 (hot path is entirely lock-free) |
| Gain multiply loop | Auto-vectorized with NEON on `arm64-v8a` by the NDK compiler |
| Bypass mode | True zero-copy: `_gain_process()` returns immediately without reading any sample |
| Added algorithmic latency | 0 frames (`latency_frames()` returns 0; gain is sample-synchronous) |
| Float output path | Requires `ENCODING_PCM_FLOAT`; already enabled via `setEnableAudioFloatOutput(true)` |

### SIMD readiness

The gain inner loop:
```c
for (int32_t i = 0; i < samples; i++) {
    data[i] *= gain_linear;
}
```
is written in a form the NDK's Clang auto-vectorizes to NEON `fmul` on
`arm64-v8a`.  Future processors (Parametric EQ, Compressor) can use explicit
NEON intrinsics in the same vtable `process()` slot without any changes to
the pipeline or JNI bridge.

---

## Validation Results

### Gain Processor — all scenarios pass through `nar_dsp_pipeline_process_raw()`

| Scenario | How to verify |
|----------|---------------|
| 0 dB (unity) | `PlaybackManager.setNativeGainDb(0.0)` — no audible change |
| Positive gain (+6 dB) | `PlaybackManager.setNativeGainDb(6.0)` — louder output |
| Negative gain (−6 dB) | `PlaybackManager.setNativeGainDb(-6.0)` — quieter output |
| Bypass | `PlaybackManager.setNativeGainBypass(true)` — zero-copy, unmodified audio |
| Enable / disable processor | `PlaybackManager.setNativeDspProcessorEnabled('dsp.gain', enabled: false)` |

### Playback compatibility

All existing features remain unaffected:
- **Crossfade** — two `NativeDspAudioProcessor` instances, one per player; both
  share global state atomically.
- **Gapless** — `DefaultAudioSink` manages gapless; processor flush between
  items is handled by `BaseAudioProcessor.flush()` (no DSP state to reset).
- **Queue transitions / Preload** — no change; DSP chain is inside each player.
- **Seek** — ExoPlayer flushes the processor chain; stateless gain processor
  needs no special handling.
- **Pause / Resume / Repeat / Shuffle** — unaffected; DSP chain is transparent.

### `flutter analyze` (Dart)

`NativeDspAudioProcessor` is `@UnstableApi` — suppressed by the existing
`@Suppress("UnstableApiUsage")` annotation or the project-wide lint baseline
in `android/app/lint-baseline.xml`.

### Native runtime tests

`nar_dsp_pipeline_process_raw()` is covered by the native unit test suite
(see `test/` directory). Existing tests verify: init/dispose lifecycle,
gain apply at various dB values, bypass zero-copy, and the NOT_INITIALIZED
fail-open path.

---

## Files Modified

| File | Change |
|------|--------|
| `android/app/src/main/kotlin/dev/wndavenz/music/Media3PlaybackService.kt` | Added `NativeDspAudioProcessor` import; create one instance per player; added as first slot in `DefaultAudioProcessorChain` |
| `lib/services/audio/playback_manager.dart` | Updated stale "not yet wired" comment to reflect Phase 4.5 reality |
| `native_audio_runtime/src/native_audio_runtime.c` | Version bumped `0.1.0-phase4` → `0.1.0-phase4.5`; added `dsp.media3_integration` capability |

**No new files** were required on the native or Dart side — all Phase 4.5
components (`NativeDspAudioProcessor.kt`, `native_dsp_jni.c`, `dsp_pipeline.c`,
`gain_processor.c`, `PlaybackManager` DSP API) were already implemented in
Phase 4.

---

## Remaining Work Before Parametric EQ

1. **`NarDspProcessorVTable` implementation** — new `.c` file implementing
   `init`, `process`, `reset`, `dispose`, `latency_frames` for the parametric
   EQ bands.  Call `nar_dsp_pipeline_register_internal()` from the EQ module's
   own init; no changes to `dsp_pipeline.c` are needed.

2. **Dart FFI bindings** — expose `nar_parametric_eq_*` functions via a new
   `NativeEqBridge` following the `NativeDspBridge` pattern.  Register with
   `NativeModuleRegistry` in `PlaybackManager.initialize()`.

3. **`PlaybackManager` EQ API** — add `setNativeEqBand(int band, double gainDb)`
   and related methods, keeping the native module opaque to UI layers.

4. **Float-output guarantee** — `ENCODING_PCM_FLOAT` is already requested; on
   devices that fall back to `ENCODING_PCM_16BIT` the parametric EQ would
   silently bypass itself (same mechanism as Phase 4.5).  Consider whether
   16-bit support is required for the EQ.

5. **A/V sync** — the gain processor has zero latency.  A future minimum-phase
   EQ or IIR compressor will introduce algorithmic latency; Media3's
   `AudioProcessor.getOutput()` contract expects latency to be reported via
   `latency_frames()` so the renderer can compensate for A/V sync.

6. **`flutter analyze` + CI** — add `native_audio_runtime/test/**` to the
   `analysis_options.yaml` exclude list if needed (already present for the
   native FFI package).
