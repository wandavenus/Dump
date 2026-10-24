# Native AutoMix fade audit

## Baseline

This audit was performed from `main` commit `999ba416dce2c51376502601ec49a042aee3dad5`
on October 24, 2026, before implementation changes. The latest repository audit,
`automix_implementation_audit_v6.md`, identifies the native fade path as open
(AM6-03).

## Findings

1. Before this branch, `CrossfadeController` drove the production fade from a
   main-looper `Handler` approximately every 16 ms. The code contained a
   native-gain callback, but `nativeFadeAvailable` was hard-coded to `false`, so
   production wrote the envelope to `ExoPlayer.volume` instead.
2. `AutomixToneAudioProcessor` is installed on both physical ExoPlayer decks in
   the custom Media3 chain. It receives float PCM after `SignalsmithStretch` and
   already exposes native fade-gain JNI helpers, but its native fade target is a
   smoothed atomic target, not a sample-timeline contract. It therefore cannot be
   treated as sample-accurate merely because the helper exists.
3. The active Media3 chain is `ToFloat → NativeDsp → StereoWiden → Reverb →
   Stretch → AutomixTone → ToInt16 → Media3 sink`. The native processors operate
   on interleaved `PCM_FLOAT`; the downstream sink receives signed 16-bit PCM.
   Both physical decks use the chain and separate stream slots.
4. Native runtime sources are compiled by `native_audio_runtime/hook/build.dart`
   into `libnative_audio_runtime.so`; `native_dsp_jni.c` provides the JNI bridge.
   The Android app packages only `arm64-v8a`, using NDK `28.2.13676358`. The
   separate CMake target is for ReplayGain/TagLib/Stretch and is not the current
   AutoMix tone/fade library.
5. Native tone availability is fail-open for linkage failures, but native fade
   capability is not independently proven by library loading alone. Configuration,
   format support, both deck processor installation, and actual buffer invocation
   must all be part of the capability result.
6. The Kotlin and native fade curves are not currently equivalent. The Kotlin
   reference includes an outgoing trim attack during the first quarter of the
   fade; `nar_automix_tone_compute_fade_gains` does not. Existing native tests
   therefore cover a helper, not full production parity.
7. The existing offline render validates only the Kotlin 16 ms volume fallback.
   No test currently proves native PCM output, buffer-partition invariance, or
   synchronization with Media3 audio buffering.

## Implementation direction

The implementation on this branch must use a native processor that owns an
explicit PCM-frame timeline rather than using JNI-call time or wall-clock time
to choose a per-sample gain. The control path will arm a transition for a
future processor frame boundary, while the processor applies the reference
envelope to every frame in order. The Kotlin volume ramp remains available as a
safe fallback until native configuration and processing are both proven.

The implementation must keep native tone and native fade capability independent,
avoid applying the same envelope through both PCM and `Player.volume`, and keep
the existing float PCM contract and dual physical stream slots.

## Baseline production flow

```text
CrossfadeController (Handler / media timeline)
  -> Media3PlaybackService callbacks
  -> AutomixToneManager + AutomixFadeManager / native JNI
  -> AudioProcessor chain on both ExoPlayers
  -> ToFloat -> NativeDsp -> StereoWiden -> Reverb -> Stretch
  -> AutomixTone -> AutomixFade / native PCM -> ToInt16 -> AudioTrack / AudioFlinger
```

## Implemented on `feat/native-automix-fade`

- Added `AutomixFadeAudioProcessor` and `AutomixFadeManager` as a separate
  per-deck PCM_FLOAT stage after `AutomixTone` and before `ToInt16`.
- Added the native C timeline processor, JNI exports, and the code-asset source
  registration. The processor uses absolute media positions converted to PCM
  frames, atomic control state, non-finite sanitization, scalar processing, and
  ARM64 NEON mono/stereo kernels.
- `CrossfadeController` now arms both physical deck processors with independent
  outgoing/incoming timeline anchors. Native mode is selected only after arm and
  configuration succeed, then the first audio-thread process counters prove that
  both processors are actually being invoked. If any proof/configuration step
  fails, the native plans are reset and the Kotlin volume envelope remains the
  sole fade path.
- Removed the old tone-stage crossfade-gain callback from the controller path, so
  native tone and native fade are independent and cannot double-apply the same
  envelope.
- Timeline state is reset or repositioned on preload seeks, media-item changes,
  explicit seeks, cancellation, completion, and processor release.
- Added regression coverage for native timeline boundaries, buffer processing,
  non-finite sample sanitization, native/fallback controller selection, and
  neutral master volume while native processing owns the fade.

## Checks completed

- `./gradlew :app:compileDebugKotlin --no-daemon` — passed; only existing project
  deprecation warnings remain.
- `./gradlew :app:testDebugUnitTest --no-daemon` — passed.
- `dart analyze lib test` — passed.
- `flutter test` — passed (277 tests).
- `dart test` in `native_audio_runtime` — passed.
- The standalone host C AutoMix test binary, compiled with the new fade source,
  passed including the new timeline/sanitization test.
- `flutter build apk --debug --target-platform android-arm64` — passed.
- `flutter build apk --release --target-platform android-arm64 --obfuscate
  --split-debug-info=build/debug-info` — passed; release APK is
  `build/app/outputs/flutter-apk/app-release.apk`.
- The packaged release `lib/arm64-v8a/libnative_audio_runtime.so` exports all
  18 expected native fade/JNI symbols (`llvm-nm -D` inspection).

## Still open

- No representative JNI/AudioTrack benchmark, fresh-install Android playback
  validation, or physical Xiaomi Mi 9T / Android 11 validation has been
  completed yet; these remain follow-up validation work after the merge.
