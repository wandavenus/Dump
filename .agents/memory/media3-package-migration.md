---
name: Media3 1.10.1 package migration
description: Audio processor classes moved from exoplayer.audio to common.audio; not removed. DefaultAudioProcessorChain still exists as public nested class.
---

# Media3 1.10.1 Audio Processor Package Migration

## The rule
In Media3 1.10.1, ALL audio processor classes moved from `androidx.media3.exoplayer.audio` to `androidx.media3.common.audio`. They were NOT removed.

**Why:** Always verify against the actual `-sources.jar` from Maven Central (`curl https://maven.google.com/androidx/media3/media3-common/1.10.1/media3-common-1.10.1-sources.jar`) before assuming a class was "deleted". The error "Unresolved reference" means wrong package 9 out of 10 times.

## How to apply
When you see "Unresolved reference" for any of these in `exoplayer.audio.*`, change to `common.audio.*`:

| Old (wrong) | Correct in 1.10.1 |
|---|---|
| `androidx.media3.exoplayer.audio.AudioProcessor` | `androidx.media3.common.audio.AudioProcessor` |
| `androidx.media3.exoplayer.audio.BaseAudioProcessor` | `androidx.media3.common.audio.BaseAudioProcessor` |
| `androidx.media3.exoplayer.audio.SonicAudioProcessor` | `androidx.media3.common.audio.SonicAudioProcessor` |
| `androidx.media3.exoplayer.audio.ChannelMixingAudioProcessor` | `androidx.media3.common.audio.ChannelMixingAudioProcessor` |
| `androidx.media3.exoplayer.audio.ChannelMixingMatrix` | `androidx.media3.common.audio.ChannelMixingMatrix` |

## DefaultAudioProcessorChain — still public, still works
`DefaultAudioSink.DefaultAudioProcessorChain` is a **public nested class** of `DefaultAudioSink`, not a removed top-level class. Use as:
```kotlin
.setAudioProcessorChain(DefaultAudioSink.DefaultAudioProcessorChain(myCustomProcessor))
```
Constructor: `DefaultAudioProcessorChain(vararg AudioProcessor)`. It appends `SilenceSkippingAudioProcessor` + `SonicAudioProcessor` after user processors — all three features (stereo widening, skip-silence, speed/pitch) are active automatically.

## DefaultAudioSink.AudioProcessorChain interface (1.10.1)
If implementing manually (rarely needed), required methods are:
- `getAudioProcessors(): Array<AudioProcessor>`
- `applyPlaybackParameters(PlaybackParameters): PlaybackParameters`
- `applySkipSilenceEnabled(Boolean): Boolean`  ← required, was missing before
- `getMediaDuration(Long): Long`
- `getSkippedOutputFrameCount(): Long`  ← replaces getPlayoutDuration (removed)

## ChannelMixingAudioProcessor limitation
`ChannelMixingAudioProcessor` (even from correct package) only handles PCM-16. With `setEnableAudioFloatOutput(true)`, it throws `UnhandledAudioFormatException` for float audio. Use `StereoWideningAudioProcessor` (custom `BaseAudioProcessor`) instead — it handles both PCM-16 and PCM-float, returns `NOT_SET` gracefully for non-stereo/unsupported formats.

## PlaybackStats fields removed in 1.10.1
- `PlaybackStats.totalBufferingTimeMs` → removed, use `0L`
- `PlaybackStats.totalErrorCount` → removed, use `0`
- `PlaybackStats.totalPlayTimeMs` ✅ still exists
- `PlaybackStats.totalRebufferCount` ✅ still exists

## setTunnelingEnabled removed
`TrackSelectionParameters.Builder.setTunnelingEnabled()` was removed. Log a no-op warning instead.
