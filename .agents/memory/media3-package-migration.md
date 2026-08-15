---
name: Media3 audio processor package layout
description: Audio processor classes are split across common.audio and exoplayer.audio in 1.11.0 — NOT all moved. Verify the actual package before assuming a class was deleted. DefaultAudioProcessorChain still exists as public nested class.
---

# Media3 Audio Processor Package Layout (verified against 1.11.0)

## The split (1.11.0, verified from release-branch source)

| Package | Audio processor classes |
|---|---|
| `androidx.media3.common.audio` | `AudioProcessor`, `AudioProcessorChain`, `BaseAudioProcessor`, `SonicAudioProcessor`, `SpeedChangingAudioProcessor`, `ChannelMixingAudioProcessor`, `ChannelMixingMatrix`, `ToInt16PcmAudioProcessor`, `GainProcessor`, `DefaultGainProvider` (+ `Sonic`, `SpeedProvider`, ...) |
| `androidx.media3.exoplayer.audio` | `ToFloatPcmAudioProcessor`, `ChannelMappingAudioProcessor`, `SilenceSkippingAudioProcessor`, `TrimmingAudioProcessor`, `TeeAudioProcessor` + sink/renderer infra (`AudioSink`, `DefaultAudioSink`, `MediaCodecAudioRenderer`, ...) |

Do **NOT** assume "everything moved to common.audio". The project itself imports
`ToFloatPcmAudioProcessor` from `androidx.media3.exoplayer.audio`
(`Media3PlaybackService.kt:51`), while `ToInt16PcmAudioProcessor` comes from
`androidx.media3.common.audio` (`Media3PlaybackService.kt:52`).

## History (why the confusion)
- `ChannelMixingAudioProcessor` + `ChannelMixingMatrix` were **ADDED in Media3 1.0.0**
  directly in `androidx.media3.common.audio` (commit eb4b6f8, Feb 2023) — never in exoplayer.audio.
- `SonicAudioProcessor` moved `exoplayer.audio` → `common.audio`, and
  `androidx.media3.exoplayer.audio.SonicAudioProcessor` was removed, **by Media3 1.6.0**
  (1.6.0 release notes: "Make `androidx.media3.common.audio.SonicAudioProcessor` final",
  "Removed `androidx.media3.exoplayer.audio.SonicAudioProcessor`").
- Earlier notes claiming "ALL audio processor classes moved in Media3 1.10.1" were WRONG —
  several classes are still in `exoplayer.audio` in 1.11.0 (see table above).

**Rule:** before assuming a class was "deleted" or moved, verify against the actual
`-sources.jar` from Maven Central (`curl https://maven.google.com/androidx/media3/media3-common/1.11.0/media3-common-1.11.0-sources.jar`
plus the matching `media3-exoplayer` jar). "Unresolved reference" usually means wrong package.

## DefaultAudioProcessorChain — still public, still works
`DefaultAudioSink.DefaultAudioProcessorChain` is a **public static nested class** of
`DefaultAudioSink` (verified 1.11.0), not a removed top-level class. Use as:
```kotlin
.setAudioProcessorChain(DefaultAudioSink.DefaultAudioProcessorChain(myCustomProcessor))
```
Constructor: `DefaultAudioProcessorChain(vararg AudioProcessor)`. It appends
`SilenceSkippingAudioProcessor` + `SonicAudioProcessor` after user processors — all three
features (stereo widening, skip-silence, speed/pitch) are active automatically.

## DefaultAudioSink.AudioProcessorChain interface (1.11.0)
`DefaultAudioSink.AudioProcessorChain` now **extends** `androidx.media3.common.audio.AudioProcessorChain`.
If implementing manually (rarely needed), required methods (verified 1.11.0 source):
- `getAudioProcessors(): Array<AudioProcessor>`
- `applyPlaybackParameters(PlaybackParameters): PlaybackParameters`
- `applySkipSilenceEnabled(Boolean): Boolean`  ← required, was missing before
- `getMediaDuration(Long): Long`
- `getSkippedOutputFrameCount(): Long`  ← replaces getPlayoutDuration (removed)

## ChannelMixingAudioProcessor limitation
`ChannelMixingAudioProcessor` (androidx.media3.common.audio) only handles PCM-16. With
`setEnableAudioFloatOutput(true)`, it throws `UnhandledAudioFormatException` for float audio.
Use `StereoWideningAudioProcessor` (custom `BaseAudioProcessor`) instead — it handles both
PCM-16 and PCM-float, returns `NOT_SET` gracefully for non-stereo/unsupported formats.

## PlaybackStats — the totalBufferingTimeMs/totalErrorCount myth
`PlaybackStats` has **no** `totalBufferingTimeMs` or `totalErrorCount` fields — they never
existed in any Media3 version (verified against release-branch `PlaybackStats.java`; the file's
last structural change was June 2023). The app's stats map sends `0L`/`0` for those keys so the
Flutter sheet renders. The real fields:
- Buffering: `getTotalRebufferTimeMs()` / `totalRebufferCount`
- Errors: `fatalErrorCount` / `nonFatalErrorCount`
- `totalPlayTimeMs` ✅ still exists
- `totalRebufferCount` ✅ still exists

## setTunnelingEnabled removed
`TrackSelectionParameters.Builder.setTunnelingEnabled()` was removed (absent in 1.11.0).
Log a no-op warning instead.
