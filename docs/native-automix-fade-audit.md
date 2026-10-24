# Native AutoMix fade audit

## Baseline

This audit was performed from `main` commit `999ba416dce2c51376502601ec49a042aee3dad5`
on October 24, 2026, before implementation changes. The latest repository audit,
`automix_implementation_audit_v6.md`, identifies the native fade path as open
(AM6-03).

## Findings

1. `CrossfadeController` currently drives the production fade from a main-looper
   `Handler` approximately every 16 ms. The code contains a native-gain callback,
   but `nativeFadeAvailable` is hard-coded to `false`, so production writes the
   envelope to `ExoPlayer.volume` instead.
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
   capability is not independently proven. Library loading alone is insufficient:
   configuration, format support, both deck processor installation, and actual
   buffer invocation must all be part of the capability result.
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
  -> AutomixToneManager / native JNI
  -> AudioProcessor chain on both ExoPlayers
  -> ToFloat -> NativeDsp -> StereoWiden -> Reverb -> Stretch
  -> AutomixTone / native PCM -> ToInt16 -> AudioTrack / AudioFlinger
```

This document is a baseline audit record. It will be updated after the native
path, parity tests, build checks, benchmarks, and device-validation status are
known.
