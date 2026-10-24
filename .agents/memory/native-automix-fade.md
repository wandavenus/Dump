---
name: Native AutoMix fade implementation
description: Timeline-safe native PCM fade wiring and verification status from 2026-10-24.
---

Branch: `feat/native-automix-fade`; draft PR: `#212`.

Implementation status:

- `AutomixFadeAudioProcessor` and `AutomixFadeManager` are separate from the
  native tone processor and are installed per physical ExoPlayer deck after
  `AutomixTone` and before `ToInt16`.
- `automix_fade_processor.c` owns an absolute media-timeline/PCM-frame cursor,
  atomic control state, equal-power envelope, trim shaping, non-finite
  sanitization, scalar fallback, and ARM64 NEON mono/stereo kernels.
- `CrossfadeController` arms both deck processors and keeps `Player.volume` as
  master/user/audio-focus gain. It requires successful arm/configuration and
  first process-call proof from both processors; otherwise it resets native
  state and uses the Kotlin volume envelope without double application.
- Seek, preload beat seek, track changes, cancellation, completion, and player
  release update/reset the native timeline state. `setTimelinePosition` must be
  followed by `arm` when a new fade is intended; the native processor preserves
  a newer arm plan while applying the pending position.
- The C host regression now covers fade boundaries, frame timing, non-finite
  input sanitization, and process status. Kotlin controller tests cover native
  configuration-proof fallback and neutral master volume in native mode.

Verified on 2026-10-24:

- `./gradlew :app:compileDebugKotlin --no-daemon`
- `./gradlew :app:testDebugUnitTest --no-daemon`
- `dart analyze lib test`
- `flutter test` (277 tests)
- `dart test` from `native_audio_runtime`
- Standalone host build/run of `native_audio_runtime/test/automix_native_c_test.c`
- `flutter build apk --debug --target-platform android-arm64`
- `flutter build apk --release --target-platform android-arm64 --obfuscate --split-debug-info=build/debug-info`
- Release APK symbol inspection found all 18 expected native fade/JNI exports in
  `lib/arm64-v8a/libnative_audio_runtime.so`.

Still open: representative JNI/AudioTrack benchmark, fresh-install playback
validation, and Xiaomi Mi 9T/Android 11 validation.
