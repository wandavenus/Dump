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

**How to apply:** Keep preview callbacks free of SharedPreferences writes,
throttle live native updates, and keep all Signalsmith state mutation on the
processor's owning audio thread. Maintain separate ramp state and duration
for speed and pitch, and reset that state on configure/flush/reset.