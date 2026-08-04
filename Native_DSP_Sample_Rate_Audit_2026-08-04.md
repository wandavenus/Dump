# Native DSP Sample-Rate Audit

Date: 2026-08-04

## Scope

Compare the real-device logs for:

- `attached_assets/flac_1785853336948.txt`
- `attached_assets/opus_1785853336973.txt`

The reported symptom was that native DSP appears to work with 48 kHz Opus but
not with FLAC and other sample rates.

## Facts from the device logs

### FLAC path

The FLAC track is selected and decoded successfully:

- input MIME: `audio/flac`
- decoder: `ffmpegLavc60.3.100-flac`
- sample rate: `44100 Hz`
- channels: `2`
- audio track: `encoding=4`, `offload=false`

Relevant log events:

```text
Selected renderer/input format: ... mime=audio/flac ... 44100Hz 2ch
Selected decoder: ... decoder=ffmpegLavc60.3.100-flac
AudioTrack initialized / PCM sink ready: ... encoding=4 44100Hz offload=false
```

This proves that FLAC is not being routed through Bit-Perfect mode or hardware
offload in this test. It also proves that the output sink accepted 44.1 kHz
float PCM.

The failure happens later, after speed/pitch and crossfeed interaction tests:

```text
speed changed speed=1.5 ...
pitch changed ... 1.5000002st
...
Stuck: pos=70361ms ... retry=1
Re-preparing decoder pipeline
Stuck: pos=70361ms ... retry=2
Re-prepare had no effect — skipping to next track
AudioDecoder RELEASED ... ffmpegLavc60.3.100-flac
```

The FLAC decoder is therefore released by the watchdog after playback stalls.
This is not a normal “DSP bypass”; it is a playback pipeline failure.

### Opus path

The Opus track is also decoded through the normal configured player:

- MIME: `audio/opus`
- decoder: `c2.android.opus.decoder`
- sample rate: `48000 Hz`
- channels: `2`
- audio track: `encoding=2`, `offload=false`

The same custom sink reports:

```text
[Stretch] onConfigure -> ACTIVE sampleRate=48000 ...
```

Speed and pitch changes complete without the FLAC watchdog stall in the
provided Opus log.

## Native DSP conclusion

The native C pipeline does not reject 44.1 kHz. The JNI bridge forwards the
actual sample rate from `NativeDspAudioProcessor` into
`nar_dsp_pipeline_process_raw_stream()`. Compressor, limiter, and loudness
processors also recalculate their sample-rate-dependent state from incoming
buffers.

The confirmed failure boundary is above the C DSP pipeline:

1. FLAC is decoded to 44.1 kHz float PCM.
2. The custom Media3 sink is selected and offload is false.
3. After speed/pitch processing, the FLAC playback position stops advancing.
4. The watchdog re-prepares and then skips the track.

The most likely failing component is the `SignalsmithStretchAudioProcessor`
path when configured at 44.1 kHz, or its interaction with Media3's
`AudioProcessingPipeline` during the speed/pitch transitions. The log contains
explicit speed/pitch changes immediately before the stall, while it does not
contain a native DSP exception or a native sample-rate rejection.

This means the original symptom should be split into two separate problems:

- **Native DSP:** the supplied app log does not contain `NativeDspAudioProcessor`
  activation or per-buffer return codes because that class currently logs with
  Android `Log.i`, not the app's `NativeLogger` channel. Its execution cannot be
  proven from these two files alone.
- **44.1 kHz playback:** definitely stalls after the stretch tests and is then
  skipped. That is the concrete failure shown by the FLAC log.

## New evidence: UI speed changes but audio tempo does not

The additional device observation is highly diagnostic:

- the Flutter position/timeline advances according to the selected speed;
- the audible FLAC stream remains at its original tempo/timbre;
- the only obvious result is that the song reaches its end sooner.

This can happen with the current implementation because timeline correction and
audio transformation are separate:

1. `TransportCommands.setSpeed` intentionally does **not** set
   `ExoPlayer.playbackParameters.speed`; Media3's Sonic processor remains at its
   default `1.0`.
2. All audible speed processing is delegated to
   `SignalsmithStretchAudioProcessor`.
3. `StretchAwareAudioProcessorChain.getMediaDuration()` still calls
   `stretchProcessor.getMediaDuration()` and can scale the reported media
   position from the speed target, even when the custom processor did not become
   active or native processing failed.

Therefore the observed combination is consistent with:

```text
speed command accepted
→ timeline/currentPosition is scaled
→ Signalsmith processor is inactive or returns a native processing error
→ audio remains pass-through (or output is dropped)
```

The FLAC file does not contain the expected
`[Stretch] onConfigure -> ACTIVE sampleRate=44100` event. The supplied Opus log
does contain the equivalent 48 kHz activation event. Because the current log
capture does not include every Android log channel, this is not by itself proof
of an inactive FLAC processor, but it is now the highest-value difference to
verify.

There is also a correctness issue in the current "fail-open" path:
`SignalsmithStretchAudioProcessor.queueInput()` increments the input/output
timeline counters and consumes the input before calling `nativeProcess()`. If
`nativeProcess()` returns an error, it publishes an empty output buffer. That
is not true pass-through; it can make the audio renderer stall while the
timeline continues to advance. This matches the FLAC watchdog behavior much
better than a native DSP coefficient problem.

The next fix must therefore make these states explicit:

- inactive processor: identity timeline and pass-through audio;
- active processor, native success: stretched audio and measured timeline ratio;
- native processing failure: safe pass-through with matching frame count and
  identity timeline, plus a visible error log.

## Additional confirmed bug

`native_audio_runtime/src/crossfeed_processor.c` does not re-derive its
biquad coefficients when the incoming buffer's sample rate changes. It only
rebuilds coefficients when parameters are pushed from Dart, whose default is
48 kHz.

This causes crossfeed frequency response to be wrong at 44.1/96 kHz, but it
does not explain the complete playback stall by itself.

## Required next diagnostic

The next device test must capture Android logcat, not only the app log, while
playing one 44.1 kHz FLAC:

```bash
adb logcat -c
adb logcat -v time \
  -s NativeDspAudioProc:D StereoWideningProc:D \
     StretchNative:D Media3:D
```

The required evidence is:

- `NativeDspAudioProc onConfigure ... active=true`
- the first native DSP call's sample rate and return code
- `StretchNative nativeCreate sampleRate=44100`
- whether `StretchNative nativeProcess` returns an error before the stall
- whether the stall still occurs with speed=1.0 and pitch=0.0

The most important isolation test is to play the same FLAC with speed and
pitch untouched at `1.0x / 0 st`. If it plays continuously, the sample-rate
problem is not the native DSP pipeline; it is the 44.1 kHz stretch path or
the transition into/out of that path.

## Audit verdict

The logs and the new observation disprove the hypothesis that native DSP is
simply hard-limited to 48 kHz. They show a more specific failure: the speed
timeline is changing independently from the audible FLAC processing, followed
by a 44.1 kHz playback stall. The implementation should first make stretch
activation/failure state correct and observable, then add actual native DSP
activation/return-code logging, and separately fix crossfeed sample-rate
coefficient refresh.