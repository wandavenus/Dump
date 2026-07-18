# Phase 8D — Player Background Rendering Refactor

## Objective

Refactor ONLY the validated Player Background rendering issues to reduce unnecessary repaint work, improve visual stability, and keep the current visual style intact.

This phase is focused on rendering efficiency and polish.

Do NOT redesign the player.
Do NOT change playback.
Do NOT change Media3.
Do NOT change DSP.
Do NOT change ReplayGain.
Do NOT change lyrics behavior.

---

# Source of Truth

Use ONLY the current repository state and the validated findings from:

- Revalidation_Report_2026_07_18.md

Focus only on the validated Player Background / rendering related issues.

Ignore:

- Rejected
- No Longer Applicable
- Do Not Fix
- unrelated findings

---

# Current Problems to Solve

Validated rendering issues include:

- shader repaint per frame
- unnecessary background redraw
- expensive effect work during invisible or near-invisible states
- repeated interpolation work inside paint/build paths
- animation work that could be isolated better
- cache behavior that may be too open-ended

---

# Main Goal

Keep the background visually identical while reducing how much work is done on each frame.

The final design should make it obvious:

- what drives the background animation
- what drives the artwork blur
- when repainting is actually needed
- which widgets are static vs animated
- where expensive effect work is isolated

---

# Core Rules

## 1. Preserve Visual Output

The background must look the same to the user.

Do not change:

- blur appearance
- fog appearance
- animation timing
- artwork look
- layering order
- player mood / atmosphere

Only change how rendering work is scheduled or isolated.

---

## 2. Isolate Repaint Scope

Any continuously animating effect must rebuild/repaint only its own subtree.

Do NOT let background animation force rebuilds of:

- controls
- lyrics
- progress
- queue
- unrelated player widgets

---

## 3. Avoid Work When Invisible

If an effect is visually invisible or below a meaningful threshold, avoid doing the expensive rendering work entirely.

Examples:

- blur below a practical opacity threshold
- shader work when fully hidden
- animation work when the widget is not active

---

## 4. Keep State Ownership Clear

Do not duplicate animation state.

Do not create parallel state sources for:

- background progress
- artwork transitions
- fog movement
- blur intensity

Use one owner per effect.

---

## 5. Be Careful With Caches

If a cache is used for background or artwork rendering:

- keep it bounded if possible
- avoid stale entries
- avoid unbounded growth unless explicitly intentional
- do not break visual continuity

---

# Suggested Refactor Targets

## A. Background Renderer

Audit the player background renderer and isolate expensive paint work.

Possible improvements:

- move static decoration out of repaint paths
- use RepaintBoundary strategically
- keep shader work local
- reduce full-tree rebuilds
- move pure calculations out of build/paint where safe

---

## B. Fog / Shader Effects

If fog or shader effects are updated every frame:

- ensure only the effect subtree repaints
- precompute values where possible
- avoid repeated lerp / transform work when inputs have not changed

Do not change the final look.

---

## C. Artwork Blur

If blurred artwork or backdrop blur is expensive:

- prevent rendering when effect is effectively invisible
- isolate the blur subtree
- avoid redundant image recomposition

---

## D. Animation Control

Make animation ownership explicit.

Possible output:

- one controller for background motion
- one controller for artwork-related transitions
- one controller for entry/exit transitions if needed

Do not add controllers unless strictly necessary.

---

# Architecture Rules

Do NOT:

- redesign the player sheet
- change mini player behavior
- change lyrics overlay behavior
- change controls behavior
- change playback state handling

This phase is about rendering efficiency and visual polish only.

---

# Safety Rules

Before changing any rendering path, verify:

- no playback logic depends on it
- no UI state is lost
- no listener chain is broken
- no animation gets stuck
- no visual regression in dark/light mode
- no unwanted jank on Mi 9T

If a change risks altering the look noticeably, stop and document it.

---

# Validation

After refactor, verify:

- flutter analyze
- player background still looks identical
- artwork blur still works
- fog still moves correctly
- animations still feel the same
- no new rebuild storms
- no regressions on Mi 9T

If possible, compare frame behavior before and after.

---

# Deliverables

## 1. Rendering Architecture Report

Explain:

- what the old rendering path was
- what the new rendering path is
- what became isolated
- what became cheaper

---

## 2. Changed Files

List every modified file.

---

## 3. Behavioral Equivalence Report

Confirm what stayed identical:

- visual appearance
- animation timing
- artwork behavior
- background layering
- player interaction

---

## 4. Risk Report

List any rendering behavior that could still differ and why.

---

## 5. Validation Report

Include:

- flutter analyze result
- build status
- runtime verification notes

---

# Stop Condition

Stop after completing the Player Background rendering refactor.

Do not continue into unrelated cleanup.
Do not start any new architecture work.
