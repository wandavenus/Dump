---
name: Media3 Option B format-guard processors
description: Why ToFloatPcmAudioProcessor/ToInt16PcmAudioProcessor bracket the custom audio processor chain, and how they were verified safe to reuse.
---

Media3 1.10.1's `ToFloatPcmAudioProcessor` (androidx.media3.exoplayer.audio) and
`ToInt16PcmAudioProcessor` (androidx.media3.common.audio) are `public final class ... extends
BaseAudioProcessor`, `@UnstableApi`, no `@RestrictTo`, zero-arg constructors, no hidden
initialization beyond the standard `AudioProcessor` lifecycle. They were deliberately made public
(commit 70e7121, Apr 2025, tracked in androidx/media#2339) specifically so apps can reuse them in
custom `DefaultAudioProcessorChain`s — there is no official recommendation against this.

**Why:** the custom chain (NativeDsp/StereoWidening/SignalsmithStretch) only does real work on
`ENCODING_PCM_FLOAT`; if the decoder ever emits int PCM, those processors silently no-op
(`AudioFormat.NOT_SET`). Bracketing the chain with ToFloat→...→ToInt16 makes the float
requirement explicit/deterministic instead of depending on `setEnableFloatOutput` always
succeeding, and hands Media3's internal SilenceSkipping/Sonic stage a guaranteed 16-bit input.

**How to apply:** chain order in `Media3PlaybackService.createConfiguredPlayer()`'s
`buildAudioSink()` is `ToFloatPcmAudioProcessor → NativeDspAudioProcessor →
StereoWideningAudioProcessor → SignalsmithStretchAudioProcessor → ToInt16PcmAudioProcessor`. Each
instance is per-player (stateful, not shareable), same as the other processors. Runtime
verification requires a real Android device build (not available in this Replit web-preview
workspace) — added `Log.i`/`NativeLogger.emit` lines in NativeDsp/StereoWidening `onConfigure` (Stretch
already logged) so logcat/System Log shows the encoding each stage actually receives; final
16-bit confirmation comes from the existing `onAudioTrackInitialized` analytics log.

Device-log lesson: `AudioTrackConfig.encoding` and the app's `NativeLogger` output
do not prove that `NativeDspAudioProcessor.queueInput()` ran. NativeDsp currently
uses Android `Log.i`, while Stretch bridges diagnostics into NativeLogger. For a
format audit, capture both channels and include native process return codes.

**Why:** a 44.1 kHz FLAC test can show a valid `PCM_FLOAT` sink and still fail
later in the custom stretch pipeline; treating the absence of a NativeLogger
message as DSP bypass gives the wrong root cause.

**How to apply:** separate format negotiation, native DSP activation, and
playback-stall evidence. Test non-unity speed/pitch independently from native
gain/EQ/crossfeed before attributing a stall to sample-rate DSP math.
