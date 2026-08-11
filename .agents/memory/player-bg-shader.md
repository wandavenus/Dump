---
name: Player background shader architecture
description: GLSL fluid shader (fluid.frag) rendering pipeline, TickerMode pause optimization, and pre-computed colour crossfade.
---

# Player Background Shader Architecture

## Pipeline (current)
```
TickerMode(enabled: blurSigma > 0.5)   ← pauses when player collapsed
  └── ClipRect → ImageFiltered(blur: sheetProgress × 22) → AnimatedBlurredPlayerBackground
        └── ProceduralFogBackground (SingleTickerProviderStateMixin)
              └── AnimationController (30-min loop)
                    └── _ShaderPainter (CustomPainter, repaint: controller)
                          ├── advanceBlend() → _recompute() → writes _c0r…_c4b
                          └── paint() → precomputes time-only values on CPU
                                        (node positions/colours, shadow & grain
                                        phases), 27 setFloat(), drawRect()
```

## Key decisions

### TickerMode pause (Phase 8D)
`TickerMode(enabled: blurSigma > 0.5)` wraps the entire background subtree in `_SheetBody.build()`. When the player is collapsed (sheetProgress=0 → blurSigma=0), all tickers in the subtree stop — zero GPU work. Resumes at sheetProgress ≈ 0.023 (blurSigma 0.5).

**Why:** Shader rendered 60fps even when player was offscreen and Opacity=0. On SD730 this is not free.

**How to apply:** TickerMode must stay in `_SheetBody.build()` wrapping the `ClipRect > ImageFiltered > AnimatedBlurredPlayerBackground` chain. If the background widget is restructured, verify TickerMode still wraps the subtree containing `_ProceduralFogBackgroundState`.

### Pre-computed colour floats (Phase 8D)
`_ShaderPainter` holds 15 pre-computed fields (`_c0r`…`_c4b`, five palette colours). Updated by `_recompute()`, called from `setColors()` and `advanceBlend()` only. `paint()` reads them directly — zero lerp arithmetic per frame.

**Why:** Lerps ran every frame unconditionally, including during stable playback (blend=1.0). Now lerps only run during the 0.8s crossfade window.

### Time-only work is precomputed on the CPU (2026-08-11, F4)
`fluid.frag` no longer takes `uTime`. Mesh node positions, the four `shiftPalette()` node colours, the ambient-shadow phase (`t*0.2 mod 2π`) and the film-grain phase (`t mod 1`) are computed in Dart (float64) inside `paint()` and uploaded as uniforms (layout 0–26, see `fog_painter.dart` header). **Why:** the old per-fragment `sin/cos/smoothstep/mix` repeated identical time-only math across all 131,072 fragments, and an unbounded GPU `uTime` degrades float32 precision. A `uTime % 200π` wrap was tried first but is NOT an exact period for the `fract()` terms (`200π·k/3 ∉ ℤ`), so it caused a periodic palette jump — do not reintroduce a wrap; keep time-only math on the CPU.

### Colour-only shader motion
`fluid.frag` uses five broad Moving Gaussian Color Fields / mesh-gradient
basins that can all cross the middle of the visible frame, with no separate
background fill. Each basin moves on a bounded path, breathes independently,
and blends through normalized Gaussian weights. Every basin independently
reweights all three palette sources over time; no basin is permanently tied to
dominant, secondary, or accent. Highlight, shadow, and the original
screen-space animated film grain add temporal colour variation without turning
the result into fast fog or liquid.

**Why:** The intended visual is living colour and inter-layer blending, not
moving fog or liquid blobs.

**How to apply:** Tune only bounded basin centers, Gaussian width/strength,
independently reweighted three-source palette mixing, restrained
highlight/shadow intensity, and the original screen-space grain. Keep all five
basin centers inside the safe interior and keep their Gaussian widths broad
enough to overlap at the edges. Do not reintroduce a separate background fill
unless edge coverage is intentionally reduced.

### Shader downscaling
Shader renders at 256×512 via `SizedBox` + `FittedBox(fit: BoxFit.cover)`. `RepaintBoundary` isolates the `CustomPaint` subtree. This was pre-existing (Phase before 8D).

### P-4 deferred
render-to-Image optimization deferred — fluid.frag needs uTime every frame; rendering to Image and only updating on colour changes would freeze the animation. RepaintBoundary is the correct isolation here.

### P-6 not needed
`ArtworkRepository` already has `_maxEntries = 300` cap on all 3 memory caches. P-6 was already fixed before Phase 8D.

### Colour crossfade on rapid skip
`setColors()` reads from pre-computed `_c*` fields as the new "old" baseline (not re-lerping from `_old`/`_cur`). This correctly captures the mid-transition position regardless of how many skips happened.
