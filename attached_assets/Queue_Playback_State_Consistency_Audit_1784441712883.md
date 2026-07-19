# Queue & Playback State Consistency Audit

## Objective

Investigate rare playback queue desynchronization bugs.

### Reported symptoms

1.  User presses **Next/Previous** but playback does not change.
2.  Audio continues playing but the UI shows a different song.
3.  The issue is **rare** and difficult to reproduce.
4.  Possible trigger combination:
    -   Crossfade enabled
    -   Repeat enabled
    -   Shuffle enabled

> **Do NOT modify code yet.**
>
> First perform a complete state-flow audit.

------------------------------------------------------------------------

# Main Goal

Determine whether there is any possibility of state divergence between:

-   Queue Manager
-   Playback Engine
-   Media3 / MediaSession
-   Crossfade Controller
-   Shuffle Logic
-   Repeat Logic
-   UI playback state
-   Notification state

------------------------------------------------------------------------

# Trace Full Playback Flow

## Next

Trace:

User taps **Next**

↓

UI command

↓

QueueManager

↓

Current index update

↓

Engine load/play

↓

Media3 state update

↓

AudioService playbackState

↓

UI rebuild

Verify every step.

------------------------------------------------------------------------

## Previous

Perform the same trace.

Pay attention to:

-   previous threshold
-   restart current song behavior
-   shuffle mode
-   repeat mode

------------------------------------------------------------------------

## Automatic Next Song

Trace:

Song reaches end

↓

Player callback

↓

CrossfadeController

↓

Queue decision

↓

Next track selection

↓

Engine transition

↓

UI state update

------------------------------------------------------------------------

# Audit Areas

## 1. Queue Source of Truth

Find:

-   where current index lives
-   where current song lives
-   where queue order lives

Check whether multiple sources exist.

Example:

-   QueueManager.currentIndex
-   PlaybackEngine.currentIndex
-   UI currentSong

Can these become different?

------------------------------------------------------------------------

## 2. Shuffle

Audit:

-   shuffled queue generation
-   shuffle index mapping
-   reshuffle timing
-   restoring shuffle state

Look for:

-   index mismatch
-   stale shuffled list
-   duplicate next item
-   invalid index

------------------------------------------------------------------------

## 3. Repeat

Audit:

-   Repeat Off
-   Repeat One
-   Repeat All

Check:

-   repeat one + crossfade
-   repeat all + shuffle
-   end-of-track callbacks

------------------------------------------------------------------------

## 4. Crossfade

Audit:

-   preload next track
-   active player
-   standby player
-   transition completion
-   current song update timing

Look for:

Audio = Song B while UI = Song A

or

UI = Song B while Engine = Song A

------------------------------------------------------------------------

## 5. Race Conditions

Search for:

-   async gaps
-   unawaited futures
-   delayed callbacks
-   timers
-   event listeners

Especially around:

-   next()
-   previous()
-   skip()
-   load()
-   play()
-   transition completion

------------------------------------------------------------------------

## 6. UI Synchronization

Verify the UI receives playback state from **one authoritative source**.

Inspect:

-   Mini Player
-   Full Player
-   Notification
-   Queue screen

Determine whether they can display different songs simultaneously.

------------------------------------------------------------------------

# Stress Test Scenarios

## Case A

-   Shuffle ON
-   Repeat OFF
-   Crossfade ON

## Case B

-   Shuffle ON
-   Repeat ALL
-   Crossfade ON

## Case C

-   Shuffle OFF
-   Repeat ONE
-   Crossfade ON

## Case D

Rapid actions:

-   Next
-   Next
-   Previous
-   Next

within a few seconds.

------------------------------------------------------------------------

# Required Deliverables

## 1. Architecture Diagram

Show:

Queue → Engine → State → UI

## 2. Possible Desynchronization Points

List every location where state can diverge.

## 3. Reproduction Probability

Classify:

-   Easy
-   Possible
-   Rare
-   Theoretical

## 4. Findings

For each finding include:

-   Status (VALID / FALSE POSITIVE / NEEDS MORE DATA)
-   File
-   Function
-   Line
-   Explanation

## 5. Fix Recommendation

Do **NOT** implement fixes.

Recommend only the safest architectural solution.

------------------------------------------------------------------------

# Constraints

Do **NOT** change:

-   Media3
-   DSP
-   ReplayGain
-   UI design

This is a **diagnosis-only audit**.
