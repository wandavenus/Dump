---
name: Lyrics full-view control hiding
description: Bottom player controls (progress/transport/secondary) hide when lyrics reach full-view — but only from a genuine user swipe-up, never from automatic scrolling.
---

The lyrics overlay expands to full-view via a scroll-offset threshold
(`offset > 150`) on the internal lyrics list, and that expand state also
drives the fade/disable of the bottom player controls (progress bar,
transport controls, secondary controls) so they don't compete visually with
full-screen lyrics.

The lyrics list also auto-scrolls programmatically to keep the current line
in view as the song plays (and possibly on other automatic events). A naive
`ScrollUpdateNotification` listener can't distinguish "user swiped up" from
"auto-follow scrolled past the threshold" — both fire the same notification
type at the same offset.

**Why:** Users reported the bottom controls disappearing on their own,
without swiping — caused by the auto-follow scroll crossing the 150px
expand threshold and triggering the same hide logic as a real swipe.

**How to apply:** When gating a hide/expand action off scroll offset,
require `notification.dragDetails != null` on the `ScrollUpdateNotification`
— this is only non-null for a real user drag on the scrollable, and null for
programmatic `jumpTo`/`animateScroll` calls. The reverse direction (offset
`< 50` → collapse/reveal controls) was left unguarded since revealing
controls again is always safe. This complements the separate swipe-down-to-
collapse feature, which already uses `ScrollEndNotification.dragDetails` for
the same reason.
