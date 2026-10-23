---
name: FFmpeg decoder integration (Phase 9)
description: How the Media3 FFmpeg decoder extension is built and wired (in-repo LGPL AAR, no GPL prebuilt), and the constraints that shaped it — read before touching decoder selection, RenderersFactory, or the AAR build.
---

## Decisions

- **Decoder AAR is built in this repo (LGPL), not downloaded.** The previous
  dependency `org.jellyfin.media3:media3-ffmpeg-decoder:1.9.0+1` publishes its
  POM as **GPL-3.0**, which conflicts with this app's "All Rights Reserved"
  `LICENSE` (audit C1). Since 1.5.42 the AAR is produced by
  `android/build-ffmpeg-jni.sh` from `androidx/media` **1.11.1** (same tag as
  `media3_version`) with FFmpeg configured without GPL/version3/nonfree, and
  committed at `android/decoder-ffmpeg/libs/media3-decoder-ffmpeg-release.aar`.
  Full design + license obligations: `docs/FFMPEG_DECODER_LGPL.md`.
  **Why:** removes the GPL-3.0 combined-work problem, removes the 1.9.0 vs
  1.11.1 version skew (M6), and drops unused decoders (incl. MagicYUV, CVE
  exposure M8) because `--disable-everything` is used.

- **Never use `ffmpeg_kit_flutter*`** — the project was archived Jan–Apr 2025
  after a licensing dispute, and it bypasses Media3's `AudioSink` chain.

- **Enabled FFmpeg decoders stay minimal:** `alac dca mlp truehd vorbis opus`.
  Do **not** enable `flac`/`aac`/`mp3`: `EXTENSION_RENDERER_MODE_PREFER` gives
  the extension priority for every format it supports, so enabling them would
  move normal playback off the platform decoders for no benefit.

- **`--enable-gpl`, `--enable-version3`, `--enable-nonfree` must never appear
  in the FFmpeg build.** The script verifies `config.h`
  (`CONFIG_GPL`/`CONFIG_VERSION3`/`CONFIG_NONFREE` = 0) and every requested
  decoder before producing the AAR, so a GPL build cannot be packaged silently.

- **The AAR is committed on purpose.** Normal and CI builds must not need an
  NDK just to compile the decoder; the script needs NDK + SDK CMake and is only
  run when `media3_version` or the decoder scope changes.

- **`android/settings.gradle` includes `:decoder-ffmpeg` only if the AAR
  exists** and sets `gradle.ext.ffmpegDecoderAarPresent`. `app/build.gradle`
  uses that for the `implementation project(':decoder-ffmpeg')` dependency and
  for `BuildConfig.MEDIA3_FFMPEG_DECODER_LINKED`. The previous
  `ffmpegDecoderEnabled` flag in `local.properties` no longer exists.

- **Release builds fail without the AAR** (`verifyFfmpegDecoderAar`, hooked to
  `preReleaseBuild`), because the target device has no usable platform ALAC
  decoder — a release without the extension cannot play lossless files.
  Deliberate bypass: `-PallowMissingFfmpegDecoder=true`
  (`ORG_GRADLE_PROJECT_allowMissingFfmpegDecoder=true` for `flutter build`).
  `.github/workflows/android.yml` builds the AAR when it is absent from the
  checkout.

- **`DefaultRenderersFactory` with `EXTENSION_RENDERER_MODE_PREFER` +
  `setEnableDecoderFallback(true)` reflectively discovers `FfmpegAudioRenderer`
  by class name at runtime.** No manual decoder-selection logic. If the AAR is
  absent the class is missing and ExoPlayer falls back to MediaCodec.

- **Reflection is kept in `FfmpegCapabilityProbe`** — never import
  `androidx.media3.decoder.ffmpeg.*` directly. Both "class not found" and
  "native lib failed to load" collapse to `available = false`;
  `moduleLinked` distinguishes them for diagnostics (`moduleLinked=false` means
  the AAR was not in the build; `true + available=false` means
  `libffmpegJNI.so` failed to load).

- **Decoder identity signal:** `decoderName.startsWith("ffmpeg")` reliably
  identifies the FFmpeg decoder in `AnalyticsListener.onAudioDecoderInitialized`.

- **APE / WavPack / TAK / Monkey's Audio are deferred** — Media3 has no
  container `Extractor` for them. Do not fold into "just add another FFmpeg
  format" without treating it as a significantly larger task.

- **Keep `MEDIA3_TAG` in sync with `media3_version`** in
  `android/app/build.gradle`. `FFMPEG_BRANCH` defaults to `release/6.0` (the
  branch Media3 1.11.1 is tested against); raise it only after an ALAC/DTS/
  TrueHD playback test.

## File map

| File | Role |
|---|---|
| `android/build-ffmpeg-jni.sh` | Builds FFmpeg static libs + the Media3 `decoder_ffmpeg` AAR; license guard; emits `build/ffmpeg-decoder-lgpl/` compliance bundle |
| `android/decoder-ffmpeg/build.gradle` | Committed Gradle wrapper exposing the committed AAR |
| `android/decoder-ffmpeg/libs/*.aar` | Committed LGPL decoder artifact (arm64-v8a shipped, other ABIs stripped by `abiFilters`) |
| `android/settings.gradle` | Conditional `include ":decoder-ffmpeg"` + `gradle.ext.ffmpegDecoderAarPresent` |
| `android/app/build.gradle` | Conditional project dep, `MEDIA3_FFMPEG_DECODER_LINKED`, `verifyFfmpegDecoderAar` release gate |
| `android/app/src/main/kotlin/.../ffmpeg/FfmpegCapabilityProbe.kt` | Runtime probe via reflection |
| `android/app/proguard-rules.pro` | Keep `androidx.media3.decoder.ffmpeg.**` |
| `docs/FFMPEG_DECODER_LGPL.md` | Build runbook, wiring, LGPL obligations, verification |
| `lib/services/native/bridges/ffmpeg_decoder_bridge.dart` | Dart API + diagnostics channels |

## Verification

Debug log after a rebuild: `Ffmpeg: Renderer config: ... moduleLinked=true
available=true version=6.0 supported=ALAC,...`. Dart capability must report
`available=true, moduleLinked=true` with `ALAC` in `supportedCodecs`.
