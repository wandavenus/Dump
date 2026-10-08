---
name: FFmpeg decoder integration (Phase 9)
description: How the official Media3 FFmpeg decoder extension was wired in, and the constraints that shaped it — read before touching decoder selection, RenderersFactory, or adding another optional native Gradle module.
---

## Decisions

- **Never use `ffmpeg_kit_flutter*`** — the whole FFmpegKit project was retired
  (archived) Jan–Apr 2025 after a licensing dispute. Use the Jellyfin prebuilt
  (`org.jellyfin.media3:media3-ffmpeg-decoder`) instead — it plugs into
  ExoPlayer's existing `AudioProcessor`/`AudioSink` chain, so the DSP pipeline
  needs no changes regardless of which decoder produced the PCM.
  **Why:** avoids shipping a dead, unpatched dependency; keeps one playback
  engine (Media3) with no bypass of the native DSP chain.

- **`androidx.media3:media3-decoder-ffmpeg` is NOT on any public Maven
  repository (Google Maven 404, confirmed).** No official prebuilt `.so`
  download exists from Google. GitHub releases for `androidx/media` also do
  NOT include prebuilt native binaries.

- **Use `org.jellyfin.media3:media3-ffmpeg-decoder:1.9.0+1` from Maven Central**
  — Jellyfin maintains a fork of the official Media3 FFmpeg extension and
  publishes it to Maven Central. The AAR includes prebuilt `libffmpegJNI.so`
  for arm64-v8a (and other ABIs). ALAC support confirmed (`ff_alac_decoder`
  present in arm64 .so). License: GPL v3.
  **Why:** eliminates NDK build requirement; 2.8 MB AAR downloaded by Gradle
  automatically; `abiFilters "arm64-v8a"` strips non-arm64 .so files.
  **How to apply:** if upgrading, check https://central.sonatype.com/artifact/
  org.jellyfin.media3/media3-ffmpeg-decoder for the latest version tag.

- **Jellyfin AAR is based on Media3 1.9.0; app uses 1.11.0.** To avoid Gradle
  version conflict, the Jellyfin dep excludes its transitive `media3-decoder`
  and `media3-exoplayer` deps so Gradle resolves everything to the pinned
  1.11.0. The FFmpeg decoder extension interfaces (`DecoderAudioRenderer`,
  `SimpleDecoder`) are stable between minor versions.
  ```groovy
  implementation('org.jellyfin.media3:media3-ffmpeg-decoder:1.9.0+1') {
      exclude group: 'androidx.media3', module: 'media3-decoder'
      exclude group: 'androidx.media3', module: 'media3-exoplayer'
  }
  ```

- **`DefaultRenderersFactory` with `EXTENSION_RENDERER_MODE_PREFER` +
  `setEnableDecoderFallback(true)` reflectively discovers `FfmpegAudioRenderer`
  by class name at runtime.** No manual "pick a decoder" logic needed —
  when the Jellyfin dep is on the classpath and `libffmpegJNI.so` loads, ExoPlayer
  uses it; otherwise falls back to platform MediaCodec ALAC automatically.

- **`BuildConfig.MEDIA3_FFMPEG_DECODER_LINKED` is hardcoded `true`** — the
  Jellyfin AAR is always on the classpath via Maven Central.
  `FfmpegCapabilityProbe.queryStatus().available` is the runtime check for
  whether `libffmpegJNI.so` actually loaded successfully.

- **Reflection is kept in `FfmpegCapabilityProbe`** — never import
  `androidx.media3.decoder.ffmpeg.*` directly. Both "class not found" and
  "native lib failed to load" collapse to `available = false`.

- **Decoder identity signal:** `decoderName.startsWith("ffmpeg")` reliably
  identifies the FFmpeg decoder in `AnalyticsListener.onAudioDecoderInitialized`.

- **APE / WavPack / TAK / Monkey's Audio are deferred** — Media3 has no
  container `Extractor` for them. Do not fold into "just add another FFmpeg
  format" without treating it as a significantly larger task.

- **`android/build-ffmpeg-jni.sh` is kept as a fallback** — if Jellyfin stops
  maintaining their prebuilt or a newer Media3 version needs it, the script
  can build a local AAR module from source with NDK. The local `:decoder-ffmpeg`
  module mechanism in `settings.gradle` was removed (Jellyfin replaces it).

## File map

| File | Role |
|---|---|
| `android/app/build.gradle` | `implementation('org.jellyfin.media3:media3-ffmpeg-decoder:1.9.0+1')` with excludes; `MEDIA3_FFMPEG_DECODER_LINKED=true` |
| `android/settings.gradle` | Comment only — no local sub-module needed |
| `android/build-ffmpeg-jni.sh` | Fallback NDK build script if Jellyfin dep unavailable |
| `android/app/src/main/kotlin/.../ffmpeg/FfmpegCapabilityProbe.kt` | Runtime probe via reflection |
| `android/app/proguard-rules.pro` | Keep `androidx.media3.decoder.ffmpeg.**` |
