---
name: Glass rendering performance
description: Backdrop blur performance rules for the Liquid Glass UI on the target Snapdragon 730.
---

Use modest backdrop blur radii for surfaces that sit above moving content. `RepaintBoundary` isolates widget repainting but does not eliminate the cost of recompositing a `BackdropFilter` when its backdrop changes.

**Why:** Large sigma values on the navbar, app bar, or mini-player glass surface can cause visible frame-time spikes during scrolling or player motion, especially on the target Snapdragon 730.

**How to apply:** Keep glass blur around sigma 12 unless a measured device profile justifies more. Honor each component toggle independently, and keep the opaque fallback genuinely opaque when a glass sub-toggle is off.