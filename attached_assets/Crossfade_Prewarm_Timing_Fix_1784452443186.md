
# Crossfade Prewarm Timing Fix

## Objective

Fix the crossfade issue where the incoming track has already advanced by about 1 second by the time fade-in becomes audible.

Observed behavior from logs:

- `prewarmStandby()` starts the standby player early
- standby is still showing `pos=0ms` when warming begins
- by the time `beginCrossfade()` starts, standby is already around `pos=1011ms`
- result: the intro of the next song is partially skipped before the fade-in is heard

This is a timing bug, not a UI issue.

---

## Root Cause to Investigate

The standby player is being warmed in a way that allows the playback position to advance before the actual crossfade begins.

The fix must ensure:

- prewarm keeps the pipeline ready
- prewarm does NOT let the standby track drift forward
- the song should start from the beginning when the fade-in actually begins

---

## Scope

Only touch the crossfade/prewarm pipeline.

Likely files:

- `android/app/src/main/kotlin/dev/wndavenz/music/crossfade/CrossfadeController.kt`
- `android/app/src/main/kotlin/dev/wndavenz/music/crossfade/PreloadManager.kt`

Do not change:

- shuffle logic
- repeat logic
- queue mapping
- Media3 service state handling
- UI
- DSP
- ReplayGain

---

## Required Investigation

Trace the exact sequence for:

1. `prewarmStandby()`
2. standby player initialization
3. any `play()`, `prepare()`, `seekTo()`, or `playWhenReady` changes
4. the moment `beginCrossfade()` starts
5. the first audible frame of the incoming track

Determine exactly where the standby track starts advancing.

---

## Fix Goal

The incoming track must still be ready for a zero-latency fade-in, but its playback position must remain at the start until the actual crossfade begins.

Choose the smallest safe fix.

Possible safe directions:

- prewarm with `prepare()` only, without advancing playback
- or prewarm with `play()` but immediately hold the position at 0 until the fade begins
- or any better minimal fix that preserves the ready pipeline without skipping intro audio

Do NOT introduce new architectural changes.

Do NOT redesign prewarm/crossfade.

---

## Verification

After the fix, verify:

- intro of the next track starts from the beginning
- crossfade still begins smoothly
- shuffle remains correct
- repeat OFF / ALL remain correct
- Repeat ONE remains correct
- no new delay is introduced at crossfade start
- no regression in manual Next / Previous

---

## Deliverables

Return:

- exact cause
- exact file(s) changed
- exact lines changed
- why the selected fix is safe
- whether prewarm still preserves zero-latency fade start

Keep the fix as small as possible.
