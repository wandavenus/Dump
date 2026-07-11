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

- **`DefaultRenderersFactory` with `EXTENSION_RENDERER_MODE_ON` +
  `setEnableDecoderFallback(true)` reflectively discovers extension renderers
  (like `FfmpegAudioRenderer`) by fully-qualified class name at runtime.** No
  manual "pick a decoder" Dart or Kotlin logic is needed or should be added —
  built-in MediaCodec is always tried first per `supportsFormatInternal()`
  ordering; the extension is silently skipped if its class isn't on the
  classpath.
  **How to apply:** if a future phase adds another Media3 extension renderer
  (video codec extension, another audio codec, etc.), do NOT touch
  `RenderersFactory` wiring logic — just get the class onto the classpath
  (optionally) and it self-registers.

- **`media3-decoder-ffmpeg` is not on Maven Central** — it must be vendored
  as a local Gradle module built against a real NDK (this project has none).
  Wiring pattern used: `settings.gradle` includes the module only if
  `android/decoder-ffmpeg/` exists as a directory; `build.gradle` adds the
  dependency only if a `ffmpegDecoderEnabled` flag in `local.properties` is
  true AND the module was actually included. Both guards must hold, so a
  stray flag can never break a build without the module.
  **Why:** lets the app build identically with or without the module present,
  on this sandbox or any other machine.

- **Kotlin capability checks use reflection (`Class.forName` +
  `Method.invoke`), never a direct `import androidx.media3.decoder.ffmpeg.*`.**
  This is the established pattern in this codebase for any optional
  dependency that might not be on the classpath (same style as the
  MIUI/OEM Hi-Res-Audio broadcast probes) — it lets the calling Kotlin file
  compile whether or not the module is vendored, and the probe just starts
  returning real data the moment the module + native `.so` are present, with
  zero code changes.

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
  custom FFmpeg-backed `Extractor`. Deliberately deferred out of Phase 9 —
  don't fold it into "just add another FFmpeg format" work without treating
  it as its own significantly larger task.
