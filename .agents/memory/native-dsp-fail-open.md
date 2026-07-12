---
name: Native DSP fail-open architecture & build-level linker bug
description: Root causes behind "first Play press does nothing" — a missing liblog link and a missing C source file in the native_audio_runtime build hook, plus the fix pattern (centralized availability guard in PlaybackManager).
---

## Root cause #1 — build-level: `__android_log_print` unresolved symbol
`native_audio_runtime/hook/build.dart` builds all C translation units via `CBuilder.library(...)`
but never links Android's `liblog`. Every processor `.c` file calls
`__android_log_print()` (from `<android/log.h>`) inside `#if defined(__ANDROID__)` debug-log
blocks. Without `-llog`, the resulting `.so` has an unresolved symbol; on Android, `dlopen()`
can fail on that unresolved reference depending on whether `liblog.so` is already resident in
the process (explains "works on 2nd press" — some other subsystem loads `liblog` first, making
the retry succeed). **Fix:** guard on `input.config.buildCodeAssets` first (it's false for
`flutter build web`, and touching `input.config.code` when it's false throws a null-check
error), then pass `libraries: [if (input.config.code.targetOS == OS.android) 'log']` to
`CBuilder.library(...)`.
**Why:** this must be fixed at the native build level (linker flag), not with a Dart-side retry
or try/catch — those only hide the symptom.
**How to apply:** any time a new C file in `native_audio_runtime/src/` calls an Android log
function, it's already covered by this one linker flag — no per-file changes needed.

## Root cause #2 — build-level: a real processor's .c file was never compiled in
`native_audio_runtime/hook/build.dart`'s `sources: [...]` list was missing
`src/loudness_processor.c` since the file's creation — it was never added even though the
Dart facade (`NativeLoudnessNorm`) and the `dsp_pipeline_io.dart` registration call
(`nar_loudness_processor_register_internal()`) both assume it exists. Because pipeline
`initialize()` registers processors in a fixed sequence and throws on the first failure, this
alone was enough to make `NativeDspPipeline.instance.isInitialized` stay `false` on every real
device — i.e. **all** native DSP (not just loudness) silently failed to initialize.
**Why this matters:** a missing source file doesn't fail the *build* (nothing else references
its symbols at C link time) — it only fails at runtime when Dart's FFI bindings try to resolve
`nar_loudness_*` symbols that were compiled out. Silent until exercised.
**How to apply:** when adding a new native DSP processor, always cross-check that its `.c` file
is actually listed in `hook/build.dart`'s `sources` — the Dart facade and header alone won't
catch its absence; only a real init-path run will.

## Fix pattern — centralize native-DSP availability guarding in PlaybackManager
`PlaybackManager` is the sole sanctioned gateway to native DSP facades (`NativeReplayGain`,
`NativeLoudnessNorm`, `NativeParametricEq`, `NativeCompressor`, `NativeLimiter`,
`NativeCrossfeed`, `NativeSoftClipper`, `NativeDspPipeline`) — no other app file should call
`bindings.nar_*` / `NativeAudioRuntime.instance` / `NativeDspPipeline.instance` directly.
Every setter/getter in `PlaybackManager` must check `NativeDspPipeline.instance.isInitialized`
before touching a facade, and fail open (no-op / safe sentinel value) when it's false, instead
of letting an FFI exception propagate into playback code (`_applyReplayGain()` →
`playSongAt()` was the exact path that turned one DSP throw into "Play does nothing").
**Why:** DSP is a purely cosmetic enhancement layer; it must never be able to block the actual
playback command reaching `Media3PlaybackBridge.play()`.
**How to apply:** any new native DSP setter/getter added to `PlaybackManager` needs the same
guard — check the existing `_dspGuard()` helper there before wiring a new one in.

## Note: `NativeDspBridge` (legacy Phase-3 module bridge) is unrelated and already safe
`lib/services/native/bridges/native_dsp_bridge.dart` is a separate, older, stub-era module
(registered via `NativeModuleRegistry`, not through `PlaybackManager`'s facades) that predates
the real DSP pipeline. It already guards every call behind its own `isAvailable` check and
never throws out of `initialize()`. Don't confuse it with the real DSP pipeline when auditing.
