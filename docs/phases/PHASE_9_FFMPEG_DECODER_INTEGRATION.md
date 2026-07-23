# Phase 9 — FFmpeg Decoder Integration

> **Superseded — read this first.** This document describes the *original*
> plan: vendoring `androidx.media3:media3-decoder-ffmpeg` as a local Gradle
> module built from source against a real Android NDK, gated by an
> `ffmpegDecoderEnabled` flag in `local.properties`. **That plan was replaced**
> before it ever shipped. The app now unconditionally depends on the Jellyfin
> prebuilt AAR (`org.jellyfin.media3:media3-ffmpeg-decoder`, Maven Central) —
> see `android/app/build.gradle` and `.agents/memory/ffmpeg-decoder-phase9.md`.
> There is no `ffmpegDecoderEnabled` flag, no local `:decoder-ffmpeg` module,
> and no NDK build step required. The architecture sections below (renderer
> wiring, capability probe, decoder-selection diagnostics) are still accurate
> — only the "Gradle wiring" and "Building the module yourself" sections that
> follow are obsolete and kept here for historical context only.

## Objective

Add a fallback audio decoder for formats Media3/ExoPlayer can demux (it
recognizes the container) but cannot decode with an on-device MediaCodec:
**ALAC, DTS, DTS-HD, TrueHD, and Vorbis/Opus edge cases.** Media3 stays the
one and only playback engine; the existing native DSP pipeline is untouched.

**Explicitly out of scope for this phase:** APE, WavPack, TAK, Monkey's Audio.
Media3 has no container `Extractor` for these formats at all — that's a
categorically bigger, unproven problem (no official reference implementation
exists) and is tracked as a separate follow-up task, not attempted here.

---

## Why not `ffmpeg_kit_flutter`

The obvious pub.dev package for "FFmpeg in Flutter" is **retired** — the
maintainer archived the entire FFmpegKit project (Jan–Apr 2025) after Google's
FFmpeg-in-Android-Studio-4.1 licensing dispute made it unsustainable. Any app
that adds it today ships a dead, unmaintained dependency with no security
patches. It was rejected outright.

## Why Google's official extension instead

`androidx.media3:media3-decoder-ffmpeg` is Google's own first-party extension,
maintained in the same `androidx/media` monorepo as ExoPlayer itself. It
provides `FfmpegAudioRenderer`, an `AudioCodecRenderer` implementation that:

- Plugs into ExoPlayer's existing renderer pipeline — no custom playback loop.
- Feeds decoded PCM through the same `AudioSink` / `AudioProcessor` chain as
  every built-in decoder, so `NativeDspAudioProcessor` (the DSP pipeline)
  needs **zero changes**.
- Is selected automatically, only when needed — see below.

---

## Architecture

```
ExoPlayer track selection
  │
  ├─ MediaCodecAudioRenderer   (built-in, tried first)
  │     supportsFormatInternal(format) → FORMAT_UNSUPPORTED_TYPE for
  │     ALAC / DTS / TrueHD / some Vorbis/Opus on most Android builds
  │
  └─ FfmpegAudioRenderer        (extension, tried only if the above declined)
        supportsFormatInternal(format):
          FfmpegLibrary.isAvailable() && FfmpegLibrary.supportsFormat(mime)
        → decodes via native libffmpegJNI.so
        → outputs PCM (16-bit or float) to the SAME AudioSink
              │
              ▼
        NativeDspAudioProcessor  (unchanged — DSP pipeline, native_audio_runtime)
        StereoWideningAudioProcessor
        SilenceSkippingAudioProcessor / SonicAudioProcessor
              │
              ▼
        Audio Output
```

### The key finding: renderer wiring already existed

`Media3PlaybackService.kt`'s `DefaultRenderersFactory` already had
`setExtensionRendererMode(EXTENSION_RENDERER_MODE_ON)` and
`setEnableDecoderFallback(true)` set from an earlier phase, anticipating this
exact integration. `DefaultRenderersFactory.buildAudioRenderers()` reflectively
looks up `androidx.media3.decoder.ffmpeg.FfmpegAudioRenderer` by fully
qualified class name and appends it to the renderer list **only if the class
is present on the classpath**, silently skipping it (with a log line)
otherwise. This means:

- **No `RenderersFactory` code changes were needed for this phase.**
- Decoder selection (built-in vs. FFmpeg) is entirely automatic — governed by
  `supportsFormatInternal()` on each renderer, tried in registration order.
  There is no manual Dart-side "pick a decoder" logic anywhere.
- The moment the FFmpeg module is vendored (see below) and its native library
  loads successfully, `FfmpegAudioRenderer` starts participating in track
  selection automatically — again, zero additional code changes.

---

## Gradle wiring (optional, guarded)

`media3-decoder-ffmpeg` is **not published to Maven Central** — Google
requires you to build it yourself against a real Android NDK because it links
against FFmpeg's LGPL/GPL-licensed code, which has redistribution
implications the official Maven artifact avoids by not existing. It must be
vendored as a local Gradle module.

This sandbox has no Android NDK, so the module cannot be built or vendored
here. The wiring is designed so the app builds and runs identically whether
or not the module has been vendored:

- **`android/settings.gradle`** — `include ":decoder-ffmpeg"` only runs if
  `android/decoder-ffmpeg/` exists as a directory.
- **`android/app/build.gradle`** — `implementation project(':decoder-ffmpeg')`
  only runs if `ffmpegDecoderEnabled=true` is set in `local.properties` **and**
  the module was actually included by `settings.gradle`. Both guards must be
  true — a stray flag left in `local.properties` on a machine without the
  module can never break the build.
- **`FfmpegCapabilityProbe.kt`** — looks up
  `androidx.media3.decoder.ffmpeg.FfmpegLibrary` via `Class.forName` +
  reflection rather than a compile-time import, so
  `Media3PlaybackService.kt` and `MainActivity.kt` compile with or without the
  dependency present. This follows the same reflection-for-optional-OEM-API
  pattern already used elsewhere in this codebase (Hi-Res Audio mode
  detection).

### Building the module yourself (runbook — requires a real NDK)

This cannot be executed in this sandbox; it's documented here for whoever
does it on a machine with Android Studio + NDK installed:

1. Clone `https://github.com/androidx/media` (branch `release`) somewhere
   outside this repo.
2. Copy `libraries/decoder_ffmpeg/` into `android/decoder-ffmpeg/` in this
   repo (rename the Gradle module to match, or keep the folder name and just
   ensure `settings.gradle`'s `project(":decoder-ffmpeg").projectDir` points
   at it — already handled by the guard above).
3. Download/clone FFmpeg source per the module's own `README.md`.
4. Run its `src/main/jni/build_ffmpeg.sh` with your NDK path and the list of
   decoders to enable. **For this phase's scope, enable only:**
   ```
   ./build_ffmpeg.sh <ffmpeg_source_path> <ndk_path> <host_platform> 21 \
       alac dca truehd vorbis opus
   ```
   (`dca` is FFmpeg's internal codec name for DTS/DTS-HD — see
   `FfmpegLibrary.getCodecName()`.) Keeping the enabled-decoder list minimal
   keeps the resulting `.so` small and avoids pulling in GPL-only codecs this
   project doesn't need.
5. Build the module's native library via its own `build.gradle` (`ndkBuild`
   task) — produces `libffmpegJNI.so` per ABI (this project only ships
   `arm64-v8a`, see `android/app/build.gradle`'s `ndk.abiFilters`).
6. Set `ffmpegDecoderEnabled=true` in `android/local.properties`.
7. Rebuild. `FfmpegDecoderBridge.instance.capabilities.available` will now be
   `true` at runtime, with zero Dart or Kotlin code changes.

### License note

FFmpeg's decoder-only build (no encoders, no GPL x264/x265) can typically be
built LGPL-compliant, but confirm the exact `--enable-*`/`--disable-*` flags
used still satisfy LGPL before shipping to production — the module's own
`README.md` has the specifics.

---

## Decoder selection diagnostics (Dart-visible)

Requirement: expose which decoder is active and why, for diagnostics — not
just "does FFmpeg exist."

```
Media3PlaybackService.kt
  AnalyticsListener.onAudioDecoderInitialized(eventTime, decoderName, ...)
    │  decoderName == "ffmpeg<version>-<codec>"  for the FFmpeg renderer
    │  (FfmpegAudioDecoder.getName() — verified against androidx/media source)
    │  any other string == a MediaCodec-based decoder name
    ▼
  FfmpegCapabilityProbe.isFfmpegDecoderName(decoderName)
  FfmpegCapabilityProbe.describeSelection(decoderName, mimeType)
    ▼
  EventEmitter.emit("ffmpegDecoderInfo", {decoderName, mimeType, isFfmpegDecoder, reason, ...})
    ▼  EventChannel musicplayer/ffmpeg_decoder_events
  FfmpegDecoderBridge.decoderInfoStream   (Dart)
    ▼
  PlaybackManager.ffmpegDecoderInfoStream  (public API)
```

Only the **active** player's decoder init is reported (dual-player crossfade
prewarm on the standby player is an implementation detail, not a user-visible
"now playing" decoder switch).

---

## Dart API surface

Per `NATIVE_BRIDGES.md`'s ownership rule, `PlaybackManager` is the only
sanctioned entry point. It talks exclusively to `FfmpegDecoderBridge`, which
in turn owns its own MethodChannel/EventChannel pair — no other file should
reference `musicplayer/ffmpeg_decoder*` directly.

```dart
// Automatic capability detection — queried once at startup by
// FfmpegDecoderBridge.initialize(), cached for the app's lifetime.
PlaybackManager.ffmpegDecoderCapabilities
  → FfmpegDecoderCapabilities(available, moduleLinked, version, supportedCodecs)

// Per-track decoder selection diagnostics.
PlaybackManager.ffmpegDecoderInfoStream
  → Stream<FfmpegDecoderInfo>(decoderName, mimeType, isFfmpegDecoder,
                               initializationDurationMs, reason)
```

`FfmpegDecoderBridge` still implements the shared `NativeModule` contract
(`moduleId`, `isAvailable`, `queryCapabilities()`) so it shows up in the
existing debug native-module list alongside `NativeDspBridge`.

---

## Error handling

- `FfmpegCapabilityProbe.queryStatus()` catches every `Throwable` from the
  reflective lookup/invocation — a half-vendored module or a native
  `UnsatisfiedLinkError` degrades to `available = false`, never crashes.
- Existing `Player.Listener.onPlayerError` → `EventEmitter.emit("error", ...)`
  is untouched and still fires for any decode failure, FFmpeg or not — this
  phase adds a new diagnostic event, it does not replace error handling.
- If the FFmpeg native library fails mid-session, ExoPlayer's own
  `setEnableDecoderFallback(true)` behavior (retry via the next capable
  renderer) still applies exactly as it does for MediaCodec failures today.

---

## What could not be verified in this sandbox

No Android SDK/NDK is installed here (see `flutter-manual-install.md` in
agent memory — same constraint as every native phase before this one). This
means:

- The `android/decoder-ffmpeg/` module itself was **not** built or vendored —
  vendoring requires cloning `androidx/media`, downloading FFmpeg source, and
  running `build_ffmpeg.sh` against a real NDK toolchain, none of which exist
  in this environment.
- The Gradle wiring, reflection probe, and event-emission code were written
  correctly per the verified official source (`FfmpegLibrary.java`,
  `FfmpegAudioRenderer.java`, `FfmpegAudioDecoder.java` — all fetched from
  `github.com/androidx/media` release branch and cross-checked for exact
  method signatures and the `decoderName` format), but an actual
  `gradle assembleRelease` with `ffmpegDecoderEnabled=true` has not been run.
- `flutter analyze` was run and is clean (Dart side only — see below);
  Kotlin cannot be compiled by the Flutter toolchain, so the guarded
  Gradle/Kotlin changes are unverified by a real build until someone with a
  full Android Studio + NDK setup completes the runbook above.

---

## Follow-up (not part of this phase)

APE, WavPack, TAK, and Monkey's Audio require writing a **custom Media3
`Extractor`** (container demuxer) — Media3 does not ship one and Google has
no official example of an FFmpeg-backed custom extractor. This is
significantly larger and riskier than wiring an existing official decoder
extension, and was deliberately deferred to its own task rather than bundled
into this one.
