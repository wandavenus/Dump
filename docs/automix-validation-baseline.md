# AutoMix Validation Baseline

Checked: 2026-11-01 (UTC+07:00)

## Reference and environment

- Clean reference checkout: commit `11e4298` (`docs(automix): blueprint eksekusi temuan terbuka v1.5.66`), app version `1.5.66`, cache schema `v23`, analyzer ABI `45`.
- Linux x86_64; Flutter `3.47.9`, Dart `3.13.7`, Clang `18.1.3`, OpenJDK `21.0.12.1`; Android NDK `28.2.13676358` is installed.
- `testdata/automix/manifest.json` already contains 12 deterministic synthetic cases. No real labeled WAV corpus is present, so the manifest does not validate real-music accuracy or close P01/P08/M08.

## M17 — native test harness

`native_audio_runtime/dart_test.yaml` now sets `concurrency: 1`, because test suites share process-global C DSP state. The documented `cd native_audio_runtime && dart test` command remains unchanged; the package config also applies when CI or another runner invokes `dart test` without an explicit concurrency flag.

- Before adding the config, the default `dart test` passed 10/10 repeated runs in this environment; the reported parallel race was not reproduced in this sample.
- With the config, default `dart test --reporter=compact` passed 10/10 repeated runs; each completed all 65 tests.
- `dart test -j 1`: 65 passed.

This makes default execution serial by construction; the repeated local passes are evidence for this environment, not a claim that every past race has been reproduced.

## Commands and results

| Command | Result |
|---|---|
| `cd native_audio_runtime && dart test -j 1` | Passed, 65 tests. |
| `cd native_audio_runtime && clang -D_POSIX_C_SOURCE=200809L -std=c11 -O1 -g -Isrc -Itest test/automix_native_c_test.c src/automix_analyzer.c src/automix_planner.c src/automix_live_tracker.c src/automix_phase_lock.c src/automix_tone_processor.c -lm -lpthread -o /tmp/automix_native_c_test_baseline && /tmp/automix_native_c_test_baseline` | Passed. The POSIX feature macro is needed for this Linux/Clang invocation to declare `nanosleep`. |
| `dart run tools/automix_bench.dart --check` | Passed, 12 synthetic cases; golden unchanged; BPM within 2%: 8/8, metre: 8/8, key: 10/10; observed mean 151.3 ms/case and peak RSS 224.3 MB on this run. |
| `TMPDIR=/dev/shm flutter test test/services/automix_service` | Passed, 149 tests. |
| `dart analyze lib test` | Passed, no issues. |
| `cd android && ./gradlew :app:testDebugUnitTest --tests 'dev.wndavenz.music.automix.AutomixTransitionPolicyTest'` (with `FLUTTER_ROOT=$HOME/development/flutter-3.47.9`, `ANDROID_HOME=$HOME/Android/Sdk`, and `ANDROID_SDK_ROOT=$HOME/Android/Sdk`) | Failed: 22 tests completed, 1 assertion failed, `early handover phrase snap can reach a full four-bar boundary` at `AutomixTransitionPolicyTest.kt:212`. This is an assertion failure, not an environment failure. |
| `tools/automix_ffmpeg_regression.sh` (with the same Flutter and Android SDK environment variables) | Could not reach audio assertions: Gradle compilation failed because the checked-in `GeneratedPluginRegistrant.java` referenced 8 plugin classes missing from the compile classpath (including `audio_session`, `gal`, `jni`, `jni_flutter`, `package_info_plus`, `permission_handler_android`, `shared_preferences_android`, and `url_launcher_android`). |

## Not run / not established

- Real-track/perceptual validation beyond fixtures is not established. The synthetic golden is a regression gate, not evidence of real-track accuracy or listener preference.
- Device capture, Mi 9T profiling, and listening tests: not run; no target-device capture was available in this workspace.
- APK: not built.
- No commit or push was made.

## Post-integration verification — working tree v1.5.67 / cache v24

This is the shared working tree after the L01, M05, L05, and M11 changes; it is not the clean reference checkout above.

| Command / evidence | Result |
|---|---|
| `dart analyze lib test` | Passed; no issues found. |
| `TMPDIR=/dev/shm flutter test test/services/automix_service` | Passed, 154 tests, including the two L05 fallback regressions, v23 cache-miss coverage, P10 plan-diff fixture, and L06 gap-cue planner regression. |
| `cd native_audio_runtime && dart test` | Passed, 65 tests with the package's serial-by-default config; rerun after L02. |
| Native C regression suite with the POSIX feature macro | Passed on host after L02/M11 changes. |
| `dart run tools/automix_bench.dart --check` | Team reports 12/12 synthetic golden cases passed; L01's 45 output slots were identical on stable and drift fixtures. |
| M05 focused Kotlin/JNI validation | Team reports 8/8 Kotlin tests and 3/3 anti-phase host-JVM + JNI fixtures passed; maximum BPM delta 0.016%, key/mode preserved, and RMS did not collapse. |
| L02 sanitizers | Not run: Clang ASan/UBSan runtime archives are missing, so the instrumented C binary could not link; the uninstrumented full C suite passed. |
| L06 focused bridge validation | Team reports 3/3 Kotlin tests passed for 12-minute window scheduling and drop-cue availability inside/outside analyzed windows. A permanent Dart regression for a 720-second plan with `analyzedFraction` 0.82 and no confident drop cue now passes; full 12-minute PCM decode through MediaCodec/JNI was not run. |
| M11 validation | Team reports host C, native Dart, QEMU ARM64 NEON/scalar parity, NDK ARM64 compile, NEON differential, and FFmpeg regression passed. |
| Broader `AutomixTransitionPolicyTest` Gradle class | 22 tests completed; one existing phrase-snap assertion failed at `AutomixTransitionPolicyTest.kt:212`. This remains an unresolved baseline failure outside the M05/M11 changes. |
| `git diff --check` | Passed on the shared working tree. |

P10's 50-track / 10-artist fixture passed: the plan changes the original order, contains each track once, has no same-artist repeat in the previous two positions, and matches the Dart reference output. This validates the fixture-level P10 criterion only; it does not stand in for P01–P09 field data, or for a user's actual 50-track library.

L02's full host C suite passed after strengthening the compound-meter fixture to provide four two-beat bars within the six-second active history. The short-history guard and expected meter 2 therefore pass without consuming samples older than the active ring buffer. No device validation was run.

## Corpus acquisition update — reported by the team, 2026-11-01

The 120-sample corpus is now downloaded and audited: 35 Candombe + 20 AAM Tiny + 35 selected FSLD loops + 30 GuitarSet clips. Meki reports that all 120 audio files passed SHA-256 checks; the local manifest audit found 120 entries, all listed audio paths present, and 2,008,569,696 bytes (about 1.87 GiB). All audio is staged under `/workspace/automix-corpora`, outside the repository. Candombe checksums match Zenodo; AAM Tiny labels include 5,776 beats, 1,444 downbeats, and chord-per-beat; the FSLD subset has metadata consensus but no event beat timestamps; GuitarSet timing comes from click track.

The 10-track AAM Tiny smoke run completed; the source-label audit found all 10 beat/downbeat event lists match the original annotations, with no corrupt IDs, files, or timestamps. Raw BPM is within ±2% on 5/10, with 38.37% mean raw error; octave-folded BPM is within 2% on 9/10: four raw octave choices (`0001`, `0080`, `1050`, `1711`) have close alternate estimates; `0620` remains a real miss at about 33.35% folded error, and its source itself changes tempo between 123 and 164 BPM. The single-key score of 2/10 is not a full key accuracy measure because all ten tracks have multiple key segments. Metre is detected as 4/4 in 3/10; the other 7 are abstentions (`null`), not wrong-meter guesses. Only two cases have a downbeat phase reference: `0192` misses by 1,283 ms and `1014` by 29 ms. These results are diagnostic on synthetic AAM, not a full-corpus P01 or event-level F1 evaluation.

Only Candombe currently counts as an independent expert-annotated event-level beat/downbeat subset. AAM labels are synthetic; GuitarSet beat/downbeat comes from click track and its chords are partly inferred. Keep these label sources and coverage separate in any metric report.

No Xiaomi device capture or playback test was possible because `adb` is unavailable. The APK permission was not needed for these checks, so no APK was built. P01–P09 real-track, listening, performance, and device criteria remain open; P10 is validated only for its synthetic fixture. L02 remains **Implemented, unvalidated** pending device/sanitizer validation; L06 remains **Implemented, unvalidated** pending a full PCM decode test.
