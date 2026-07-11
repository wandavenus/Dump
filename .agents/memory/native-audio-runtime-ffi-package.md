---
name: native_audio_runtime FFI package (Phase 3 native foundation)
description: How the dedicated dart:ffi package for future DSP/FFmpeg was structured, and native-assets build quirks hit in this sandbox.
---

## Decision: separate `package_ffi` package, not code embedded in the app

`native_audio_runtime/` (local path dependency of the main app) hosts the
native runtime foundation for future DSP/FFmpeg modules — lifecycle,
version, capability, and a native-side module registry only, no processing
logic. Scaffolded with `flutter create --template=package_ffi` (the
non-deprecated FFI template; `plugin_ffi` is deprecated).

**Why:** Official Flutter convention for reusable `dart:ffi` code; uses
Dart's native-assets build hooks (`hook/build.dart` + `package:hooks` +
`package:native_toolchain_c`) instead of hand-written CMake/Gradle wiring in
`android/app/src/main/cpp/` — required **zero** changes to the app's
`android/` Gradle files. Requires `flutter config --enable-native-assets`
(a one-time, environment-level toggle) or the build hook is silently
ignored.

**How to apply:** Any future standalone dart:ffi native code in this
project should follow the same pattern — new package with `package_ffi`
template, sources added to `hook/build.dart`'s `CBuilder.library(sources:
[...])` list, consumed via a local `path:` pubspec dependency.

## Web-safety pattern for dart:ffi + web target

The main app also builds for web, where `dart:ffi` doesn't exist. Fix:
conditional export keyed on `dart.library.ffi`:
```dart
export 'src/runtime_impl_unsupported.dart'
    if (dart.library.ffi) 'src/runtime_impl_io.dart';
```
Shared types (enums/classes with no ffi import) live in a third file so
both implementations can use them identically. Verified `flutter build web`
still succeeds with this package as a live dependency.

## native_toolchain_c only looks for a binary literally named `clang`

On Linux hosts, `native_toolchain_c`'s compiler resolver searches for
`clang` (or MSVC) on PATH — it does not fall back to `gcc`/`cc` even if
present. This container only has `gcc`. To actually run `dart test` for a
native-assets package locally (proving the C logic really executes, for
the *host* platform, not Android), symlink a throwaway `clang -> gcc` in a
scratch dir prepended to PATH for that one invocation — verification-only,
not a project/CI requirement. Android builds use the NDK's own clang and
don't have this issue.

## Env this project has no way to verify

No Android SDK/NDK/gradle toolchain in this Replit container (`flutter
doctor` reports it missing). Actual `flutter build apk` — proving Android
cross-compilation and native-asset bundling into the APK — cannot be run or
checked here. Document this explicitly rather than silently mocking; the
host-platform `dart test` above is the closest real verification available.

## CAS state-machine bug pattern worth remembering

A lock-free init guard written as a single `compare_exchange(UNINITIALIZED
-> INITIALIZING)` silently breaks re-initialization after a prior
`dispose()` (state is now `DISPOSED`, not `UNINITIALIZED`, so the CAS always
fails and callers wrongly get "already initialized"). Needs a CAS **loop**
that treats both `UNINITIALIZED` and `DISPOSED` as valid starting states.
Caught only by writing a test that disposes then re-initializes.
