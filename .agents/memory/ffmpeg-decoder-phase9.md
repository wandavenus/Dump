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

- **`androidx.media3:media3-decoder-ffmpeg` IS published on Google Maven** —
  the AAR (`FfmpegLibrary`, `FfmpegAudioRenderer`) is a standard Maven dep at
  `implementation 'androidx.media3:media3-decoder-ffmpeg:1.10.1'`.
  The native runtime (`libffmpegJNI.so`) is NOT included in the AAR; it must
  be built from `androidx/media` source using `android/build-ffmpeg-jni.sh`
  and placed at `android/app/src/main/jniLibs/arm64-v8a/`.
  **Why:** the old design (local `:decoder-ffmpeg` sub-module) was based on
  wrong information that the AAR wasn't on Maven; replaced with a direct Maven
  dep that always puts the class on the classpath.
  **How to apply:** if version is bumped, update both the Maven dep in
  `app/build.gradle` and the `MEDIA3_TAG` in `build-ffmpeg-jni.sh` together.

- **`BuildConfig.MEDIA3_FFMPEG_DECODER_LINKED` is now hardcoded `true`** —
  the AAR class is always linked, so the flag just means "class is on classpath".
  `FfmpegCapabilityProbe.queryStatus().available` is the runtime check for
  whether `libffmpegJNI.so` actually loaded. These are two separate signals.
  **Why:** the old conditional (based on `findProject(':decoder-ffmpeg')`)
  always returned false in every build because the local module never existed,
  making the flag misleading.

- **`DefaultRenderersFactory` with `EXTENSION_RENDERER_MODE_PREFER` +
  `setEnableDecoderFallback(true)` reflectively discovers extension renderers
  (like `FfmpegAudioRenderer`) by fully-qualified class name at runtime.** No
  manual "pick a decoder" Dart or Kotlin logic is needed or should be added —
  built-in MediaCodec is always tried first per `supportsFormatInternal()`
  ordering; the extension is silently skipped if its .so isn't in the APK.
  **How to apply:** if a future phase adds another Media3 extension renderer
  (video codec extension, another audio codec, etc.), do NOT touch
  `RenderersFactory` wiring logic — just get the class onto the classpath
  (optionally) and it self-registers.

- **Reflection is kept in `FfmpegCapabilityProbe`** even though the class is
  always on the classpath, because a build without `libffmpegJNI.so` still
  compiles and runs cleanly: the reflective `isAvailable()` call returns false
  and ExoPlayer falls back to MediaCodec automatically.
  **Why:** avoids a direct `import androidx.media3.decoder.ffmpeg.*` that would
  make compile-time failures more likely if the AAR is temporarily unavailable.

- **`build-ffmpeg-jni.sh` builds ALAC-only** with `--disable-everything` then
  selectively enables: decoder=alac, demuxer=mov,caf, parser=alac,
  protocol=file. This minimizes `.so` size for the arm64-v8a target.
  **How to apply:** if another FFmpeg codec is needed later, add its
  `--enable-decoder/demuxer/parser` flags to the script; do not enable broadly.

- **Decoder identity signal:** ExoPlayer's `AnalyticsListener
  .onAudioDecoderInitialized` reports `decoderName` as `decoder.getName()`.
  For the FFmpeg extension this is literally `"ffmpeg" + version + "-" +
  codecName` (verified against `FfmpegAudioDecoder.java` source) — a reliable
  `decoderName.startsWith("ffmpeg")` check distinguishes it from any
  MediaCodec-based decoder name. Useful anywhere "which decoder is active"
  needs to be reported without adding new native plumbing.

- **APE / WavPack / TAK / Monkey's Audio are a different, larger problem**
  than ALAC/DTS/TrueHD/Vorbis/Opus: Media3 has no container `Extractor`
  (demuxer) for them at all, and there is no official example of a
  custom FFmpeg-backed `Extractor`. Deliberately deferred — don't fold it
  into "just add another FFmpeg format" work without treating it as its own
  significantly larger task.

## File map

| File | Role |
|---|---|
| `android/app/build.gradle` | Maven dep + `MEDIA3_FFMPEG_DECODER_LINKED=true` |
| `android/settings.gradle` | No local sub-module; comment only |
| `android/build-ffmpeg-jni.sh` | NDK build script → `libffmpegJNI.so` arm64 ALAC |
| `android/app/src/main/jniLibs/arm64-v8a/` | Drop built `.so` here (gitignored) |
| `android/app/src/main/kotlin/.../ffmpeg/FfmpegCapabilityProbe.kt` | Runtime probe via reflection |
| `android/app/proguard-rules.pro` | Keep `androidx.media3.decoder.ffmpeg.**` |
