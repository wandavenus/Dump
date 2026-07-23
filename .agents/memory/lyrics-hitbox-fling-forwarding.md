---
name: Lyrics bottom-hitbox drag forwarding with fling
description: How forwarded (non-native) drags in the lyrics bottom hit-box areas get real scroll momentum on release, matching a normal list drag.
---

Several transparent GestureDetectors sit over the lyrics/queue overlay area (bottom-zone scroll relay, fixed bottom controls, and an external gesture-inset relay reaching into player_sheet from outside the SafeArea). They don't own a ScrollController — they forward raw drag deltas into the live lyrics ScrollPosition via `LyricsDragHandle.scrollByDelta()` → `ScrollPosition.jumpTo()`.

`jumpTo()` has no built-in momentum, so without extra work the list stops dead the instant the finger lifts, unlike a genuine drag directly on the list (which flings via `ScrollPositionWithSingleContext.goBallistic()`).

**Fix:** on `onVerticalDragEnd`, forward the release velocity through `LyricsDragHandle.flingByVelocity(primaryVelocity)`, which negates it and calls `goBallistic()` on the live `ScrollPositionWithSingleContext` — giving forwarded drags the same fling feel as scrolling the list directly.

**Why:** `DragUpdateDetails.delta.dy`/`DragEndDetails.primaryVelocity` are in on-screen finger space; `ScrollPosition` methods (`jumpTo` target, `goBallistic` velocity) are in scroll-offset space, which is the negation. This sign flip must be applied consistently or the fling direction is backwards.

**How to apply:** Any time a new transparent overlay is added that forwards drags into a list it doesn't directly own, wire both `onVerticalDragUpdate` (delta forwarding) and `onVerticalDragEnd` (velocity forwarding via `goBallistic`) together — one without the other produces either no scroll or no momentum.

Same applies to the queue overlay's forwarded drags: even though `_queueScrollController` is attached directly to its `ListView` (so a *direct* touch on the queue list already flings natively), drags *forwarded* from the bottom hit-box areas still go through manual `ctrl.jumpTo()` and need the same `goBallistic(-velocity)` treatment on drag-end — being attached to a real ListView does not give forwarded/synthetic drags momentum for free.
