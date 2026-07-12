---
name: FFmpeg decoder integration (Phase 9)
description: How the official Media3 FFmpeg decoder extension was wired in, and the constraints that shaped it — read before touching decoder selection, RenderersFactory, or adding another optional native Gradle module.
---

## Decisions

- **Never use `ffmpeg_kit_flutter*`** — the whole FFmpegKit project was retired
  (archived) Jan–Apr 2025 after a licensing dispute. Use Google's own
  `androidx.media3:media3-decoder-ffmpeg` extension (`FfmpegAudioRenderer`)
  instead — it plugs into ExoPlayer's existing `AudioProcessor`/`AudioSink`
  chain, so the DSP pipeline needs no changes regardless of which decoder
  produced the PCM.
  **Why:** avoids shipping a dead, unpatched dependency; keeps one playback
  engine (Media3) with no bypass of the native DSP chain.

- **`androidx.media3:media3-decoder-ffmpeg` is NOT on any public Maven
  repository (Google Maven, Maven Central, etc.)** — confirmed HTTP 404 on
  `dl.google.com/dl/android/maven2`. The AAR + native `libffmpegJNI.so` must
  be built from the `androidx/media` source tree using Android NDK via
  `android/build-ffmpeg-jni.sh`, then dropped as a local Gradle module at
  `android/decoder-ffmpeg/`. The GitHub releases for androidx/media also do
  NOT include prebuilt `.so` binaries.
  **Why:** this was verified by actually attempting the Maven download; there
  is no shortcut — NDK is required.
  **How to apply:** if version is bumped, update `MEDIA3_TAG` in
  `build-ffmpeg-jni.sh` to match.

- **`DefaultRenderersFactory` with `EXTENSION_RENDERER_MODE_PREFER` +
  `setEnableDecoderFallback(true)` reflectively discovers extension renderers
  (like `FfmpegAudioRenderer`) by fully-qualified class name at runtime.** No
  manual "pick a decoder" Dart or Kotlin logic is needed or should be added —
  when `android/decoder-ffmpeg/` is absent, ExoPlayer silently falls back to
  the platform MediaCodec ALAC decoder (supported on Android 10+ / minSdk 29).
  **How to apply:** if a future phase adds another Media3 extension renderer,
  do NOT touch `RenderersFactory` wiring — just get the class+.so onto the
  classpath via a new local module and it self-registers.

- **`build-ffmpeg-jni.sh` builds ALAC-only** with `--disable-everything` then
  selectively enables: decoder=alac, demuxer=mov,caf, parser=alac,
  protocol=file. This minimizes `.so` size for the arm64-v8a target. The
  script also runs `assembleRelease` via Gradle to produce a proper AAR (Java
  wrapper + .so combined), which becomes the local module's `libs/` artifact.
  **How to apply:** if another FFmpeg codec is needed later, add its
  `--enable-decoder/demuxer/parser` flags; do not enable broadly.

- **Reflection is kept in `FfmpegCapabilityProbe`** — never import
  `androidx.media3.decoder.ffmpeg.*` directly. Both "class not on classpath"
  and "native lib failed to load" collapse to `available = false` so callers
  always get a single yes/no answer with no compile-time dependency on the
  optional module.

- **Decoder identity signal:** `decoderName.startsWith("ffmpeg")` reliably
  identifies the FFmpeg extension decoder in
  `AnalyticsListener.onAudioDecoderInitialized`. Useful for diagnostics
  without adding new native plumbing.

- **APE / WavPack / TAK / Monkey's Audio are deferred** — Media3 has no
  container `Extractor` (demuxer) for them. Do not fold into "just add another
  FFmpeg format" work without treating it as a significantly larger task.

## File map

| File | Role |
|---|---|
| `android/app/build.gradle` | `ffmpegDecoderEnabled = findProject(':decoder-ffmpeg') != null`; conditional dep |
| `android/settings.gradle` | Conditional `include ":decoder-ffmpeg"` when dir exists |
| `android/build-ffmpeg-jni.sh` | NDK build script → produces `android/decoder-ffmpeg/` local module |
| `android/decoder-ffmpeg/` | Output of build script; gitignored; contains AAR with .so embedded |
| `android/app/src/main/kotlin/.../ffmpeg/FfmpegCapabilityProbe.kt` | Runtime probe via reflection |
| `android/app/proguard-rules.pro` | Keep `androidx.media3.decoder.ffmpeg.**` |
