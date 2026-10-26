# AGENTS.md

## Repo at a glance
- Flutter local music player, package `musicplayer`, Android app id `dev.wndavenz.music`; app version lives in `pubspec.yaml` and must match the top changelog entry.
- Android-first: target only Xiaomi Mi 9T / Redmi K20 (arm64-v8a, Android 11 / MIUI 12). Do not add other-device or other-ABI compatibility paths.
- Web (`web/`, `server.js`, `build/web/`) is a preview surface only; Android MediaStore/FFI features are unavailable there.
- Start with `docs/ARCHITECTURE.md` for the system map, then `.agents/memory/MEMORY.md` for implementation history and layer maps (`dart-layer-map.md`, `kotlin-android-layer-map.md`, `native-c-layer-map.md`). Docs can lag; code wins.
- `opencode.json` also loads `GEMINI.md`; its generic `build_runner` / mockito instructions are not configured in this repo — don't run them.

## Commands
- Deps: `flutter pub get`
- Analyze: `dart analyze lib test`; avoid analyzing from repo root because it pulls in SDK/generated checkouts. Local wrapper: `./analyze-high-value.sh lib test`. CI: `flutter analyze --no-pub --no-fatal-warnings --no-fatal-infos`.
- Flutter tests: `flutter test`; one file: `flutter test test/services/lyrics_service/lrc_parser_test.dart`.
- Kotlin tests: `cd android && ./gradlew :app:testDebugUnitTest`; one class with `--tests "dev.wndavenz.music.queue.QueueManagerTest"`. Needs JDK 21, Android SDK 36, NDK 28.2.13676358, CMake 3.22.1.
- Native C/FFI tests: `cd native_audio_runtime && dart test` (Dart >=3.11 and a working `clang`; the native-assets hook compiles `src/*.c`).
- AutoMix offline audio regression: `tools/automix_ffmpeg_regression.sh` (requires `ffmpeg`, `ffprobe`, Java).
- APK (CI): `flutter build apk --release --target-platform android-arm64 --obfuscate --split-debug-info=build/debug-info`. `setup-flutter.sh` / `build-apk.sh` are Replit-specific (`/home/runner/...`) — don't assume they work in Termux/Codespaces.
- This Termux workspace has Flutter (`/data/data/com.termux/files/usr/opt/flutter`), Android SDK (`/data/data/com.termux/files/usr/opt/android-sdk`), Java, `dart`, and `clang`; analyze/test/gen-l10n work locally.
- NEVER run `flutter build apk` (or any APK build) in this environment — user directive, permanent. Builds belong to CI/devcontainer/Replit.
- Web preview: `node server.js` serves prebuilt `build/web`; rebuild only when explicitly asked with `flutter build web --release --base-href /`.
- l10n: edit `lib/l10n/app_{en,id}.arb`, run `flutter gen-l10n`; don't hand-edit generated `app_localizations*.dart`.

## Architecture rules
- Call path: `lib/main.dart` → `AudioService` / `PlaybackManager` → `Media3PlaybackBridge` → Kotlin `Media3PlaybackService` → `NativeDspAudioProcessor` / JNI → `native_audio_runtime` C DSP.
- Kotlin Media3 owns playback, queue, shuffle, repeat, sleep timer, crossfade, and effects. Dart mirrors state over streams; never re-implement queue/shuffle logic in Dart.
- `lib/services/audio/media3/media3_playback_bridge.dart` is the only Dart file that may touch `musicplayer/*` Method/EventChannels. Route through `PlaybackManager` / `AudioService`.
- DSP is C in `native_audio_runtime/src` (FFI on host, JNI on Android): the audio thread does no allocation/logging, cross-thread knobs are atomic, and DSP failures must fail open.
- New C files must be listed in `native_audio_runtime/hook/build.dart` (the build source of truth, not Gradle); `native_dsp_jni.c` is Android-only. `android/app/src/main/cpp/CMakeLists.txt` builds the separate ReplayGain/TagLib/Stretch JNI modules.
- Native Parametric EQ was removed; the Band EQ uses Android's system Equalizer. Don't reintroduce a second EQ backend.
- App state is `ValueNotifier` + `Stream` + `setState`; there is no Provider/Bloc/Riverpod.
- Startup order in `lib/main/main.dart` is deliberate (LogService → permissions → warmups → audio init). Don't add awaited platform-channel calls that can block startup.
- Web guards are intentional: e.g. `MediaStoreService.getSongs()` throws `MissingPluginException` on web; treat it as an empty library.

## Workflow
- Every behavior change: add a new top entry in `lib/pages/settings_page/changelog_data.dart` and bump `version:` in `pubspec.yaml` to the same version. Never reuse the previous version.
- After any repo-changing session, update the relevant `.agents/memory/*.md` topic and its `MEMORY.md` index.
- `lib/` Dart edits: use Dart MCP `hot_reload`; `hot_restart` after `initState`, global/static state, or `main()` changes (`.agents/rules/flutter-hot-reload.md`).
- Android verification is a full uninstall + fresh install; don't treat upgrade-in-place as a valid test.
- All GitHub workflows are `workflow_dispatch` only; Noisegraph suites are dispatched manually. Don't assume push/PR CI.
