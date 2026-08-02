---
name: Crossfade cancellation and volume
description: Crossfade lifecycle invariants for cancellation, user volume changes, and audio-focus ducking.
---

Crossfade cancellation must rebuild the authoritative full queue on the promoted
player before pause, stop, or crossfade-setting changes continue. Equal-power
automation must read an effective target dynamically on each tick, including
user volume changes and the active audio-focus duck factor.

**Why:** During promotion the standby player temporarily owns a one-item queue.
Without rebuilding after cancellation, pause/resume or navigation can become
stuck on that item. A target captured once at fade start can also overwrite a
user volume change or undo audio ducking on the next tick.

**How to apply:** Keep cancellation before transport commands, clear the standby
state, rebuild the active queue when the promoted player is partial, and expose
one effective volume target for all crossfade ticks.