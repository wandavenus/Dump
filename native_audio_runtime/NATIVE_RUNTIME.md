# native_audio_runtime — Phase 3 Native Runtime Foundation

## What this package is

A standalone Dart/Flutter **FFI package** (`flutter create --template=package_ffi`,
the current, non-deprecated Flutter template for shareable `dart:ffi` code —
`plugin_ffi` is deprecated in favor of this one). It gives the main app's
future native modules (DSP, FFmpeg, FFT, ReplayGain, Visualizer, Resampler,
…) a single, thread-safe native runtime to initialize, query, and register
against — **without any DSP or FFmpeg logic**. That logic is explicitly out
of scope for this phase; see `lib/services/native/NATIVE_BRIDGES.md` in the
main app for the module bridges that consume this package.

## Why a separate package, not code embedded in the main app

Chosen deliberately over embedding native code directly in
`android/app/src/main/cpp/`:

- **Official convention.** `package_ffi` is Flutter's own recommended
  structure for reusable `dart:ffi` code — it ships its own build hook
  (`hook/build.dart`), its own C sources, and its own versioned public API,
  independent of the app's Gradle/CMake wiring.
- **Native Assets, not manual Gradle/CMake.** This template uses Dart's
  *native assets* build hooks (`package:hooks` + `package:native_toolchain_c`)
  instead of a hand-maintained `CMakeLists.txt` + `externalNativeBuild` block
  in `android/app/build.gradle`. The main app's Android project needed **zero
  Gradle changes** — `flutter pub get` + `flutter config --enable-native-assets`
  is the entire integration surface. This is a meaningfully smaller footprint
  than the JNI-first design this phase's spec explicitly supersedes.
- **Reusability.** If a second app in this workspace ever needs the same
  runtime, it becomes a normal pub dependency instead of copy-pasted native
  code.
- **Testability.** Because native assets are built per-target, `dart test`
  inside this package compiles and runs the **real C code for the host
  platform** (see "What was actually verified" below) — something a
  Gradle-only `android/app/src/main/cpp/` setup cannot give you without an
  emulator or device.

The tradeoff: native assets require `flutter config --enable-native-assets`
(now enabled in this environment) and a reasonably recent Flutter/Dart SDK.
Both are satisfied here (Flutter 3.44.5 / Dart ^3.12.2).

## Public API

`package:native_audio_runtime/native_audio_runtime.dart` exports a single
singleton, `NativeAudioRuntime.instance`:

| Member                     | Purpose                                                             |
|-----------------------------|----------------------------------------------------------------------|
| `initialize()`              | Idempotent init of the shared native runtime.                       |
| `dispose()`                 | Idempotent teardown.                                                 |
| `isAvailable` / `isInitialized` | Whether the native library loaded & initialized on this platform. |
| `version`                   | Native runtime version string.                                       |
| `capabilities`              | Placeholder capability list — **all `supported: false`** in Phase 3. |
| `registerModule(id)`        | Native-side module ledger; used by `NativeDspBridge` / `FfmpegDecoderBridge`. |
| `registeredModuleIds`       | Ids registered so far, in order.                                      |

All types (`NativeRuntimeStatus`, `NativeRuntimeCapability`,
`NativeRuntimeException`) live in `lib/src/runtime_types.dart` and are pure
Dart — no `dart:ffi` import — so they are safe to use from any platform.

## Web safety (important)

`dart:ffi` does not exist on the web compile target. The main app also
builds for web (`flutter build web`, the "Watch & Rebuild Web" workflow).
To keep that working, this package's public entry point conditionally
exports one of two implementations with an **identical API**:

```dart
export 'src/runtime_impl_unsupported.dart'
    if (dart.library.ffi) 'src/runtime_impl_io.dart';
```

- `dart.library.ffi` is present on Android/iOS/Linux/macOS/Windows → the real
  `dart:ffi`-backed implementation (`runtime_impl_io.dart`) is used.
- It is absent on web (dart2js/dartdevc) → `runtime_impl_unsupported.dart` is
  used instead: same API, `isAvailable` always `false`, no `dart:ffi` import
  anywhere in that file or its dependencies.

Verified: `flutter build web` (via the "Watch & Rebuild Web" workflow)
completes successfully after this package was added as a dependency and
after every subsequent edit to the bridges that consume it.

## Native C API

`src/native_audio_runtime.h` / `.c` — lifecycle, version, capability, and a
fixed-size module registry. No audio processing. Thread-safety:

- `native_runtime_init()` — lock-free CAS loop; exactly one caller performs
  real init even under concurrent calls; safe to call again after a prior
  `dispose()` (re-initialization is a valid transition, not just the
  first-ever call — this required a second CAS iteration, not a single
  compare-and-swap, to admit both `UNINITIALIZED → INITIALIZING` and
  `DISPOSED → INITIALIZING`).
- `native_runtime_dispose()` — safe no-op if never initialized or already
  disposed.
- `native_runtime_register_module()` — guarded by a small mutex around the
  fixed-size module table only (the hot init/dispose path stays lock-free).

## What was actually verified in this environment

This sandbox has **no Android SDK/NDK/gradle toolchain** installed
(`flutter doctor` reports the Android toolchain missing; no `sdkmanager`,
no `$ANDROID_HOME`). That means an actual `flutter build apk` — the one
build that would prove Android cross-compilation, Gradle native-asset
bundling, and the `.so` loading on-device — **could not be run or verified
here**. This is the single largest unverified assumption in this phase.

What *could* be verified, and was:

1. **The C code itself compiles cleanly** — `gcc -std=c11 -Wall -Wextra`
   with zero warnings.
2. **The native runtime's actual logic runs correctly on the host** —
   `dart test` inside this package triggers the real native-assets build
   hook, which compiles `src/native_audio_runtime.c` for the *host*
   platform (Linux x64, using the container's `gcc`) and links it into the
   test binary. All 8 tests in `test/native_audio_runtime_test.dart`
   exercise the real compiled C code, including the concurrent-init
   thread-safety contract and the DISPOSED→re-init transition. This is not
   a mock — it is the actual shipped C source, just compiled for a
   different target than Android.
   - Note: `native_toolchain_c`'s compiler resolver looks specifically for
     a binary named `clang` (or MSVC) on the host `PATH`; this container
     only has `gcc`. Verifying locally therefore required a throwaway
     `clang -> gcc` symlink in a scratch directory prepended to `PATH` for
     that one `dart test` invocation — this is a local verification
     workaround only, not a project or CI requirement, and nothing in the
     shipped package depends on it. Android builds use the NDK's own
     `clang`, which does not have this issue.
3. **`flutter analyze` is clean** across the main app and this package
   (including its `example/`).
4. **`flutter build web`** (via the "Watch & Rebuild Web" workflow) succeeds
   with this package as a live dependency, proving the web-safe conditional
   export actually avoids pulling in `dart:ffi` on that target.
5. **`flutter config --enable-native-assets`** was enabled in this
   environment — required for Flutter's build tooling to honor
   `hook/build.dart` at all; without it, the hook is silently ignored and
   the native library would never be built or bundled.

What remains unverified and should be checked on a real build (Android
Studio / a machine with the Android SDK+NDK, or CI):

- That `flutter build apk` actually invokes this package's `hook/build.dart`
  for the `android_arm64` target and bundles the resulting `.so` into the
  APK (native assets + AGP 9.0.1 interaction has not been exercised here).
- That `NativeAudioRuntime.instance.isAvailable` is actually `true` on a
  real Android device (i.e. the `.so` loads and `native_runtime_init()`
  runs) — in this sandbox, the app never runs on Android at all, so this
  bridge code has only been exercised via `flutter analyze` (static) and the
  host-target `dart test` above (real execution, wrong target platform).
- Whether `minSdk 28` / `arm64-v8a`-only (`ndk.abiFilters`) need any
  corresponding restriction declared in this package (native assets
  currently builds for whatever `code_assets` reports as the target
  architecture list from the consuming app; not independently confirmed to
  respect the main app's `abiFilters` restriction to `arm64-v8a` only).
