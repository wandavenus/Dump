# Addendum --- Repeat ONE × Crossfade Investigation

## Background

A new reproducible issue has been discovered after the original audit.

### Reproduction

Configuration:

-   Shuffle = ON
-   Repeat = ONE
-   Crossfade = 8 seconds

Observed behavior:

Song A

↓

Crossfade begins

↓

Playback transitions to **Song B**

Expected behavior:

Song A

↓

Crossfade

↓

Song A starts again from the beginning (Repeat ONE semantics)

This issue is now reproducible and is no longer considered merely
theoretical.

------------------------------------------------------------------------

# Objective

Perform a focused trace of the interaction between:

-   Repeat ONE
-   Crossfade
-   QueueManager
-   PreloadManager
-   ExoPlayer repeat logic

Do NOT implement any fixes yet.

Update the previous audit document with the new findings instead of
creating a separate report.

------------------------------------------------------------------------

# Investigation Tasks

## 1. Trace Repeat ONE flow

Trace from:

Track approaches its end

↓

CrossfadeController.maybeCrossfadeOut()

↓

Every function involved until the standby player starts playback.

Document every decision point.

------------------------------------------------------------------------

## 2. Determine who selects the "next" track

Identify exactly where the standby preload target is chosen.

Possible locations:

-   CrossfadeController
-   PreloadManager
-   QueueManager
-   TransportCommands
-   ExoPlayer

For each location explain:

-   Which API is used
-   Which index is selected
-   Whether Repeat ONE is considered

------------------------------------------------------------------------

## 3. Verify ExoPlayer behavior

Determine whether:

current.nextMediaItemIndex

already respects Repeat ONE,

or whether additional logic is required.

Use official Media3 / ExoPlayer behavior as the reference.

Do not assume.

------------------------------------------------------------------------

## 4. Identify the root cause

If Song B is selected instead of Song A:

Explain precisely why.

Examples:

-   Repeat ONE ignored
-   nextMediaItemIndex unsuitable
-   preload executed before repeat logic
-   queue rebuilt incorrectly
-   active player state mismatch

------------------------------------------------------------------------

## 5. Check for side effects

If the fix requires changing preload selection:

Verify that it will NOT break:

-   Shuffle
-   Repeat ALL
-   Repeat OFF
-   Manual Next
-   Manual Previous
-   Automatic queue advance
-   Existing crossfade flow

------------------------------------------------------------------------

# Deliverables

Update the original audit document.

Do NOT create a new report.

Revise:

-   Findings table
-   DP-6 status
-   Root cause analysis
-   Fix recommendations

If DP-6 is confirmed:

Change its status appropriately and explain why.

If DP-6 is disproven:

Explain why and provide evidence.

Include:

-   file
-   function
-   line numbers
-   event timeline
-   confidence level

------------------------------------------------------------------------

# Constraints

Do not modify code.

This is a diagnosis and audit update only.
