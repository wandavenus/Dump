---
name: Phase 6 Dynamics Processing
description: Compressor, Limiter, Soft Clipper — what changed in the pipeline and tests
---

# Phase 6 Dynamics Processing

## What was done

All C, Dart, and test code for Phase 6 was already in place. The only work needed was updating the test file to match the new pipeline reality.

## Key facts for future agents

**Pipeline now has 5 slots** (in order):
- [0] dsp.gain (Phase 4)
- [1] dsp.peq (Phase 5)
- [2] dsp.compressor (Phase 6)
- [3] dsp.limiter (Phase 6)
- [4] dsp.soft_clipper (Phase 6)

**Total pipeline latency = 63 frames** (from the limiter's 64-frame look-ahead buffer; `NAR_LIMITER_LOOKAHEAD_FRAMES − 1 = 63`). Any test asserting `totalLatencyFrames == 0` is wrong post-Phase 6.

**Thread safety pattern:**
- Compressor + Limiter: double-buffer + acquire/release dirty flag (params pre-computed on control thread)
- Soft Clipper: atomic int32 bit-pattern trick (single float parameter, same as gain)

**Dart API**: all via `PlaybackManager` only — `NativeCompressor`, `NativeLimiter`, `NativeSoftClipper` must not be imported directly from UI/service code.

**Why:**
- Limiter uses 64-frame look-ahead circular buffer per channel (max 8 ch) — this is stack-allocated in NarLimiterState, no heap alloc on audio thread.
- Compressor is feed-forward (reads input level, not output) with log-domain envelope → predictable, transparent behavior.
- Soft Clipper's tanhf is only called for samples exceeding the threshold (transparent fast path for well-mastered audio).

## Test isolation pattern

When testing a single processor in isolation, disable all others explicitly:
```dart
NativeDspPipeline.instance.setProcessorEnabled('dsp.gain', enabled: false);
NativeDspPipeline.instance.setProcessorEnabled('dsp.peq', enabled: false);
NativeDspPipeline.instance.setProcessorEnabled('dsp.compressor', enabled: false);
NativeDspPipeline.instance.setProcessorEnabled('dsp.limiter', enabled: false);
NativeDspPipeline.instance.setProcessorEnabled('dsp.soft_clipper', enabled: false);
// then enable only the one under test
```

## Documentation
`docs/PHASE_6_DYNAMICS_PROCESSING.md` — comprehensive: algorithms, threading model, performance table, Dart API reference, remaining work.
