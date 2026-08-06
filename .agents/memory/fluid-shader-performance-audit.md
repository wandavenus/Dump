---
name: Fluid shader performance audit
description: Performance constraints and hotspots in the procedural player background shader.
---

## Rule

Keep the fluid background at a bounded 256×512 render target and treat
time-only shader work as a candidate for per-tick precomputation. The dominant
fragment costs are radial distance falloffs, repeated palette rotation, grain
hashing, and continuous refresh-rate animation.

**Why:** On the target Snapdragon 730, even the downscaled shader executes about
131,072 fragments per frame; repeated square roots and trigonometric work are
multiplied by every visible frame.

**How to apply:** Preserve `TickerMode` when collapsed and profile on the Mi 9T
before changing visual behavior. Prioritize moving `shiftPalette()` and node
motion calculations out of the fragment path, then consider squared-distance
falloffs, cheaper grain, or adaptive frame cadence. See
`Fluid_Shader_Performance_Audit_2026-08-06.md` for the detailed findings.