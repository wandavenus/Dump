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
                          ├── advanceBlend() → _recompute() → writes _c0r…_c2b
                          └── paint() → 0 lerps, 12 setFloat(), drawRect()
```

## Key decisions

### TickerMode pause (Phase 8D)
`TickerMode(enabled: blurSigma > 0.5)` wraps the entire background subtree in `_SheetBody.build()`. When the player is collapsed (sheetProgress=0 → blurSigma=0), all tickers in the subtree stop — zero GPU work. Resumes at sheetProgress ≈ 0.023 (blurSigma 0.5).

**Why:** Shader rendered 60fps even when player was offscreen and Opacity=0. On SD730 this is not free.

**How to apply:** TickerMode must stay in `_SheetBody.build()` wrapping the `ClipRect > ImageFiltered > AnimatedBlurredPlayerBackground` chain. If the background widget is restructured, verify TickerMode still wraps the subtree containing `_ProceduralFogBackgroundState`.

### Pre-computed colour floats (Phase 8D)
`_ShaderPainter` holds 9 pre-computed fields (`_c0r`…`_c2b`). Updated by `_recompute()`, called from `setColors()` and `advanceBlend()` only. `paint()` reads them directly — zero arithmetic per frame.

**Why:** Lerps ran every frame unconditionally, including during stable playback (blend=1.0). Now lerps only run during the 0.8s crossfade window.

### Shader downscaling
Shader renders at 256×512 via `SizedBox` + `FittedBox(fit: BoxFit.cover)`. `RepaintBoundary` isolates the `CustomPaint` subtree. This was pre-existing (Phase before 8D).

### P-4 deferred
render-to-Image optimization deferred — fluid.frag needs uTime every frame; rendering to Image and only updating on colour changes would freeze the animation. RepaintBoundary is the correct isolation here.

### P-6 not needed
`ArtworkRepository` already has `_maxEntries = 300` cap on all 3 memory caches. P-6 was already fixed before Phase 8D.

### Colour crossfade on rapid skip
`setColors()` reads from pre-computed `_c*` fields as the new "old" baseline (not re-lerping from `_old`/`_cur`). This correctly captures the mid-transition position regardless of how many skips happened.
