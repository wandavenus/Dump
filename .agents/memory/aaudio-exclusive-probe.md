---
name: AAudio exclusive/MMAP runtime probe
description: How to actually determine whether a device grants AAudio exclusive/low-latency mode, and how new dlopen-based native diagnostics get wired into this project's native_audio_runtime package.
---

## The problem
Whether a device truly supports AAudio SHARING_MODE_EXCLUSIVE + MMAP cannot be
determined from static SoC/OEM/Android-version info, and Java's public
`AudioTrack` API cannot expose the actual granted sharing mode — only the NDK
C `aaudio.h` API can (`AAudioStream_getSharingMode` after actually opening a
stream). AAudio silently downgrades to SHARED when the vendor HAL/OEM policy
doesn't honor an exclusive request; there is no "is it supported" query, only
"open a stream and see what you got".

## The approach taken
Added a diagnostic-only probe (`native_runtime_aaudio_probe()` and friends) to
`native_audio_runtime` that `dlopen("libaaudio.so")` + `dlsym()`s the handful
of AAudio C entry points needed at **runtime**, manually mirroring AAudio's
frozen public C ABI (stable since API 26) inside the new `.c` file, instead of
`#include <aaudio/AAudio.h>` or linking `-laaudio` at build time.

**Why:** this Replit container has no Android NDK/SDK, so header
availability and link-time correctness for `-laaudio` can't be verified here.
dlopen/dlsym fails closed (probe just reports "unavailable") instead of
risking a build break — matches this project's established
"native DSP fail-open" convention (see `native-dsp-fail-open.md`).

**How to apply:** opens a real output stream requesting
EXCLUSIVE + LOW_LATENCY, reads back what was actually granted, closes it
immediately. Exposed to the Debug page in Settings (not the Equalizer page)
as a manual "Uji Sekarang" button — safe to call repeatedly, does not
interfere with playback. Real confirmation of behavior still requires
building and running on a physical Android device; this environment can only
verify `flutter analyze` + `flutter build web` (the native aaudio_probe.c
path is `#if defined(__ANDROID__)`-gated and unreachable on web).

## Reusable pattern for adding a new native_audio_runtime diagnostic/module
1. New `src/<name>.h` + `.c` pair (not folded into `native_audio_runtime.h`,
   which intentionally never grows module-specific APIs per its own header
   comment).
2. Add the new `.c` file to `hook/build.dart`'s `sources` list; add any new
   system libraries (e.g. `'dl'`) to the Android-only `libraries` list.
3. `ffigen.yaml` lists only the main header as entry-point, but bindings are
   **hand-maintained** (no libclang in this environment) — manually add the
   new function signatures to `lib/native_audio_runtime_bindings_generated.dart`
   in the same `@ffi.Native<...>()` style as existing entries, regardless of
   what ffigen.yaml's entry-points say.
4. Add a Dart facade class in both `lib/src/runtime_impl_io.dart` (real FFI)
   and `lib/src/runtime_impl_unsupported.dart` (web stub) — both are already
   wholesale-exported by `native_audio_runtime.dart`'s conditional export, so
   no separate export line is needed once the class exists in both files.
