---
name: Pitch/speed slider transition smoothing
description: Rules for keeping live pitch and playback-speed changes smooth across Flutter UI and the Signalsmith audio thread.
---

The pitch and playback-speed sliders use two paths: a lightweight live preview
while dragging, and a committed setter on release for persistence. The native
Signalsmith processor treats incoming values as audio-thread targets and ramps
both parameters over a short frame-count-based interval before applying them.

**Why:** Applying a large slider delta at one audio block boundary changes the
STFT target and/or output-frame ratio abruptly, which is audible as a click,
stutter, or broken transition. Persisting or invoking MethodChannel work for
every pointer event also creates unnecessary scheduling pressure.

**Always-on STFT invariant:** `SignalsmithStretchAudioProcessor` must run the
STFT engine from the first sample of every stream and keep it engaged until a
flush/reset. Do NOT reintroduce a dry bypass path or a mid-stream
bypass→STFT/STFT→bypass splice. Signalsmith's input→output latency is one
STFT block plus one interval (~150 ms at the default 48 kHz preset); calling
`seek()` with the already-heard bypass tail does not align it, because the
first output is that tail again and the synthesis window still needs one
interval to warm up. The audible result is exactly the dropout/repeat/crackle
on the first speed or pitch slider move. At unity the engine stays active;
parameter changes then only move its targets, so there is no splice to click.

**Audio-thread rule:** Never log, allocate, or call back into Kotlin from the
JNI process/set-pitch paths. `bridgeToSystemLog()` posts work to the main
looper; doing that per buffer or per parameter update can underrun the audio
thread. Keep diagnostics to create/destroy/configure and one-shot error paths.

**How to apply:** Keep preview callbacks free of SharedPreferences writes,
throttle live native updates, and keep all Signalsmith state mutation on the
processor's owning audio thread. Maintain continuous (never restarted)
smoothing for speed and pitch, initialise applied values on configure, and
reset them on configure/flush/reset.
