---
name: FFmpeg decoder integration (Phase 9)
description: Local JNI build of Media3's FFmpeg extension (android/decoder-ffmpeg + build-ffmpeg-jni.sh) replaces the GPL Jellyfin AAR; read before touching decoder selection, RenderersFactory, FFmpeg native flags, or the JNI packaging.
---

# FFmpeg decoder — local JNI build (2026-10-24)

## What changed

The decoder used to come from the Jellyfin community AAR
(`org.jellyfin.media3:media3-ffmpeg-decoder:1.9.0+1`, Maven Central, **GPL v3**,
built on Media3 1.9.0 while the app runs 1.11.1). It is now built inside the
repo:

- `android/decoder-ffmpeg/` — Android library module.
  - Wrapper classes (`FfmpegLibrary`, `FfmpegAudioDecoder`,
    `FfmpegAudioRenderer`, `FfmpegDecoderException`) vendored verbatim from
    androidx/media **1.11.1** (Apache 2.0; headers retained).
  - `src/main/jni/ffmpeg_jni.cc` vendored from the same tag (Apache 2.0).
- `android/build-ffmpeg-jni.sh` — cross-compiles FFmpeg **n8.1.3** for
  arm64-v8a / API 27 and links `libffmpegJNI.so`. Configured with
  `--disable-gpl --disable-nonfree --disable-version3`; FFmpeg reports
  “License: LGPL version 2.1 or later”. No GPL component is linked.
- `android/settings.gradle` includes `:decoder-ffmpeg`; `app/build.gradle` uses
  `implementation project(':decoder-ffmpeg')`. No Maven AAR, no exclusion
  block, no `ffmpegDecoderEnabled` flag.
- The `.so` is **not committed**. `:decoder-ffmpeg:buildFfmpegJni` runs the
  script from `preBuild`; output is
  `src/main/jniLibs/arm64-v8a/libffmpegJNI.so` (≈1.3 MB). The FFmpeg checkout
  and static libs live in `.ffmpeg-build/` (gitignored).
- `MEDIA3_FFMPEG_DECODER_LINKED=true` remains hardcoded because the module is
  always on the classpath; `FfmpegCapabilityProbe.queryStatus().available` is
  the runtime check for whether the native lib actually loaded.

## Decisions kept from the original phase

- **Never use `ffmpeg_kit_flutter*`** — retired Jan–Apr 2025, unpatched.
- **`androidx.media3:media3-decoder-ffmpeg` is not on Maven.** Building from
  source is the only official-JNI path; using Jellyfin’s AAR was only a
  convenience, and its GPLv3 license was an audit blocker.
- **Reflection stays in `FfmpegCapabilityProbe`** — never import
  `androidx.media3.decoder.ffmpeg.*` directly. Missing class and unloadable
  `.so` both collapse to `available=false`; ExoPlayer falls back to platform
  MediaCodec.
- **`DefaultRenderersFactory` self-registration is untouched** —
  `EXTENSION_RENDERER_MODE_PREFER` + `setEnableDecoderFallback(true)` in
  `Media3PlaybackService.kt`; no manual renderer wiring.
- **Decoder identity:** `decoderName.startsWith("ffmpeg")`.
- **APE / WavPack / TAK / Monkey’s Audio stay deferred** — no Media3 container
  `Extractor`; separate, larger task.

## Native build details that matter

- Decoders enabled: `alac dca truehd mlp vorbis opus` — matches
  `FfmpegCapabilityProbe.PROBE_MIME_TYPES`. The script verifies each
  `ff_<name>_decoder` symbol and that `JNI_OnLoad` is exported.
- Link flags: `-nostdlib++ -Wl,-Bsymbolic -Wl,--gc-sections --no-undefined`.
  The result depends only on `libandroid`, `liblog`, `libm`, `libdl`, `libc`
  (no `libc++_shared.so`), so no extra C++ runtime is packaged.
- FFmpeg `n8.1.3` also postdates the `CVE-2026-8461` fix (8.1.2); MagicYUV is
  not enabled anyway.
- Rebuild manually with:
  `bash android/build-ffmpeg-jni.sh --clean`.
  `--force-link` reuses cached static libs and only relinks (used by Gradle).
- `build-ffmpeg-jni.sh` needs NDK 28.2.13676358 + network on first run. The
  build task fails loudly if the toolchain or FFmpeg checkout is unavailable.
- License obligations for redistribution: LGPL-2.1-or-later text, attribution,
  and a source offer for the exact FFmpeg tag. Replaces the former GPLv3
  blocker (AUDIT_REPORT C1).

## Verification (2026-10-24)

- `bash android/build-ffmpeg-jni.sh --clean` built and verified
  `libffmpegJNI.so` (1.3 MB); `llvm-nm` shows `JNI_OnLoad` exported and no
  `libc++_shared.so` dependency.
- Deleted the `.so` and ran `:decoder-ffmpeg:assembleDebug`: Gradle re-ran the
  script from `preBuild` before `mergeDebugJniLibFolders`, and the AAR contained
  `jni/arm64-v8a/libffmpegJNI.so`.
- `:app:assembleDebug` → BUILD SUCCESSFUL; `app-debug.apk` contains
  `lib/arm64-v8a/libffmpegJNI.so` and `FfmpegAudioRenderer` in the dex.
- `:app:assembleRelease` → BUILD SUCCESSFUL (R8 + resource shrinking);
  `app-release.apk` (27 MB) still contains `libffmpegJNI.so` and the
  `-keep class androidx.media3.decoder.ffmpeg.**` rule keeps
  `FfmpegAudioRenderer` instantiable.
- `:app:testDebugUnitTest` → BUILD SUCCESSFUL; `dart analyze lib test` → no
  issues; `flutter test` → 274 tests passed.
- Device verification still pending: install fresh (uninstall first) and check
  `adb logcat | grep -E "Ffmpeg|ffmpeg_jni"` for `available=true` plus the five
  codec names.

## File map

| File | Role |
|---|---|
| `android/decoder-ffmpeg/build.gradle` | Library module; Java 17, minSdk 27, `buildFfmpegJni` Exec hooked to `preBuild` |
| `android/decoder-ffmpeg/README.md` | Provenance, rebuild commands, license notes |
| `android/decoder-ffmpeg/src/main/java/.../ffmpeg/*.java` | Vendored Media3 1.11.1 wrapper (Apache 2.0) |
| `android/decoder-ffmpeg/src/main/jni/ffmpeg_jni.cc` | Vendored JNI bridge |
| `android/decoder-ffmpeg/src/main/jniLibs/arm64-v8a/libffmpegJNI.so` | Generated (gitignored) |
| `android/build-ffmpeg-jni.sh` | FFmpeg cross-compile + JNI link + verification |
| `android/settings.gradle` | `include ":decoder-ffmpeg"` + library plugin version |
| `android/app/build.gradle` | `implementation project(':decoder-ffmpeg')` |
| `android/app/src/main/kotlin/.../ffmpeg/FfmpegCapabilityProbe.kt` | Reflection probe |
| `android/app/proguard-rules.pro` | Keep `androidx.media3.decoder.ffmpeg.**` |
| `lib/services/native/bridges/ffmpeg_decoder_bridge.dart` | Dart status bridge |
