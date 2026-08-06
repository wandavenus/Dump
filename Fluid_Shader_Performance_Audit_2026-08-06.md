# Fluid Shader Performance Audit — 2026-08-06

## Scope

Static audit of:

- `assets/shaders/fluid.frag`
- `lib/widgets/player/player_background/artwork.dart`
- `lib/widgets/player/player_background/fog_painter.dart`
- `lib/widgets/player/player_sheet/state.dart`
- `lib/widgets/unified_morph_player.dart`

Target device: Xiaomi Mi 9T/K20, Snapdragon 730, MIUI 12/Android 11.

No shader source or runtime code was changed during this audit. This is a
source-level review; no GPU trace or on-device frame-time measurement was
available in this pass.

## Executive summary

The shader is already downscaled to a 256×512 render target:

```text
256 × 512 = 131,072 fragments per frame
131,072 × 60 fps ≈ 7.9 million fragments per second
```

That downscale is the largest existing optimization and should be preserved.
There are no texture samples, loops, dynamic array accesses, or large kernels.
The main cost is instead a high number of transcendental/radial operations per
fragment, some of which are mathematically identical for every pixel and can
be computed once per animation tick.

## Findings

| ID | Severity | Area | Status |
|---|---|---|---|
| FSA-F01 | High | Four radial weights use `length()` + `smoothstep()` per fragment | Open |
| FSA-F02 | High | Four `shiftPalette()` calls repeat time-only palette work per fragment | Open |
| FSA-F03 | Medium | Shadow and grain each add a per-fragment `sin()`; vignette adds another `length()` | Open |
| FSA-F04 | Medium | Eight node-position `sin()`/`cos()` values are time-only but written in shader code | Open |
| FSA-F05 | Medium | Animation drives the shader continuously at display refresh rate | Expected |
| FSA-F06 | Conditional high | Legacy `PlayerSheet` wraps the shader in `ImageFiltered.blur` up to sigma 22 | Conditional |
| FSA-F07 | Low | `setFloat()` calls and `RepaintBoundary` are not the bottleneck | Informational |

## FSA-F01 — Four radial weights use expensive distance math

**Location:** `fluid.frag:41-44`

Each fragment evaluates:

```glsl
length(uv - p00)
length(uv - p10)
length(uv - p01)
length(uv - p11)
```

Each `length(vec2)` requires a dot-product followed by a square root. The
result then goes through `smoothstep()`. This is four square roots and four
smoothstep evaluations for every one of the 131,072 fragments.

The weight normalization at line 54 also performs a per-fragment vector
expression and division:

```glsl
vec3 col = (...) / totalW;
```

**Impact:** This is a significant fragment ALU cost on a mid-range mobile GPU,
especially because it runs for every visible animation frame.

**Potential optimization:** Use squared distance (`dot(d, d)`) and a squared
radius falloff, accepting a small visual curve change. This removes the four
square roots. Alternatively reduce the four-node model to three nodes if the
visual result remains acceptable.

## FSA-F02 — `shiftPalette()` repeats time-only work four times per fragment

**Location:** `fluid.frag:18-27`, calls at `fluid.frag:47-50`

The four node colors depend only on `uTime` and the uniform palette values. They
do not depend on `uv`, yet `shiftPalette()` is invoked inside `main()` for
every fragment. Across those calls the shader evaluates:

- four `mod(progress, 3.0)` operations;
- four branch chains;
- four `smoothstep()` operations;
- four palette `mix()` operations.

The branch condition is uniform for a frame, so it should not cause divergent
pixel lanes, but the source still exposes a large amount of repeated
per-fragment work. The SkSL/GLSL optimizer may hoist some uniform-invariant
expressions; that cannot be assumed without inspecting generated GPU code or
profiling the target device.

**Impact:** This is the clearest avoidable hotspot in the shader. The palette
rotation can be evaluated once per animation tick on the Dart side and passed
as node colors, or the shader can receive precomputed node colors directly.

**Tradeoff:** Passing four precomputed node colors increases uniform writes.
That is still generally cheaper than repeating `mod`/branch/smoothstep/mix over
131,072 fragments. A simpler alternative is to remove continuous palette
rotation and keep only the spatial blend.

## FSA-F03 — Per-fragment shadow, grain, and vignette math

### Shadow

**Location:** `fluid.frag:57-58`

The shadow mask adds one `sin()` and one `smoothstep()` per fragment:

```glsl
uv.y + 0.2 * sin(uv.x * 3.0 + t * 0.2)
```

### Film grain

**Location:** `fluid.frag:61-63`

The grain adds:

- one `mod()` on time;
- one `dot()`;
- one `sin()`;
- one `fract()`;
- a full-color mix.

The `mod(t, 1.0)` component is uniform and can be calculated outside the
fragment shader, but the hash `sin(dot(...))` remains per-pixel.

### Vignette

**Location:** `fluid.frag:66-67`

The vignette adds a fifth `length()`/square root per fragment. At only 18%
strength it is visually subtle, so it is a good candidate for approximation or
removal if frame time is tight.

**Potential optimization:** Replace the grain hash with a cheaper hash that
does not use a trigonometric function, or disable grain on the target device.
Replace the vignette distance with a squared-distance approximation or fold it
into a static overlay.

## FSA-F04 — Node motion contains eight time-only trigonometric calls

**Location:** `fluid.frag:35-38`

The four node positions use eight `sin()`/`cos()` calls. They depend only on
`uTime`, not on the fragment coordinate:

```glsl
sin(t * ...)
cos(t * ...)
```

If the shader compiler does not hoist these expressions, every fragment repeats
the same eight trigonometric calculations. Even if the compiler does hoist
them, keeping these values in the fragment shader makes that optimization
backend-dependent.

**Potential optimization:** Compute the four node positions once per tick in
Dart and pass them as uniforms, or reduce the motion to fewer shared phase
values. The preferred implementation should avoid adding excessive uniform
traffic; four packed `vec4` values or two packed `vec4` values are enough for
the node coordinates.

## FSA-F05 — Continuous 60 FPS animation

**Location:** `artwork.dart:57-66`, `fog_painter.dart:179-203`

`AnimationController` drives a repaint continuously while the widget is active.
`TickerMode` correctly pauses the ticker when the `PlayerSheet` is collapsed:

```dart
TickerMode(enabled: blurSigma > 0.5, ...)
```

The active `UnifiedMorphPlayer` path renders
`AnimatedBlurredPlayerBackground` directly and does not use the legacy
`PlayerSheet` `ImageFiltered` wrapper. The shader therefore remains active while
the unified player is visible, including the mini-player/full-player morph.

**Impact:** Expected for a living background, but the cost is paid at the
display refresh rate even when the visual delta between frames is small.

**Potential optimization:** If device profiling shows GPU pressure, update the
shader at 30 FPS or use an adaptive frame cadence while keeping the widget
visible. Do not restore rendering while fully collapsed; the existing
`TickerMode` gate is valuable.

## FSA-F06 — Conditional runtime blur around the legacy PlayerSheet path

**Location:** `lib/widgets/player/player_sheet/state.dart:201-213`

The legacy `_SheetBody` path wraps the background in:

```dart
ImageFiltered(
  imageFilter: ImageFilter.blur(
    sigmaX: blurSigma,
    sigmaY: blurSigma,
  ),
  child: AnimatedBlurredPlayerBackground(...),
)
```

`blurSigma` reaches 22 while expanded. A blur is an additional compositing
pass and may require offscreen processing over the child bounds. It can cost
more than the shader itself on some GPUs.

Repository search found no construction site for `PlayerSheet`; the active
bottom-navigation path uses `UnifiedMorphPlayer`. Therefore this is a
conditional/legacy risk, not currently proven active runtime cost. If
`PlayerSheet` is reintroduced, the blur should be profiled separately and not
attributed to `fluid.frag`.

## FSA-F07 — What is already cheap or correctly optimized

- Render target is 256×512, not full-screen 1080p.
- There are no texture reads.
- There are no loops.
- There are no large convolution kernels in the shader.
- Dart-side color crossfade is precomputed outside `paint()`.
- The 18 `setFloat()` calls and one `drawRect()` are small compared with the
  fragment workload.
- `RepaintBoundary` isolates the animated background's raster invalidation,
  although it does not eliminate the GPU work caused by changing `uTime`.
- `shouldRepaint => true` is not the primary bottleneck because the painter is
  intentionally driven by its repaint `Listenable`.

The compiled shader copies in `build/web` and `build/app/intermediates` are
SkSL/Flutter runtime-effect artifacts rather than source GLSL. Their differing
hashes from `assets/shaders/fluid.frag` are expected and are not evidence of a
stale source copy by themselves.

## Recommended order of work

1. **Measure on the Mi 9T/K20 first.** Capture Flutter frame timing and GPU
   frame time with the active unified player visible. Static analysis cannot
   prove whether the shader compiler already hoists the time-only expressions.
2. **Move `shiftPalette()` out of the fragment shader.** This is the strongest
   source-level optimization because it removes four repeated palette
   transformations per fragment.
3. **Remove or approximate the five radial square roots.** Start with the four
   node weights; keep the vignette unchanged until visual comparison is done.
4. **Replace or gate the grain hash.** It is low visual strength but adds a
   trigonometric operation to every fragment.
5. **Only then consider 30 FPS/adaptive updates.** This reduces total work
   without changing the shader's per-pixel complexity.
6. **Profile the legacy blur separately** if `PlayerSheet` becomes active.

## Conclusion

`fluid.frag` is not large, but it is ALU-heavy for its size. The two most
important hotspots are the four radial `length()` falloffs and the four
time-only `shiftPalette()` calls executed from the fragment path. The existing
256×512 downscale and collapsed-state `TickerMode` are good defenses and
should remain. No evidence currently shows that `setFloat()`, Dart color
interpolation, or the `RepaintBoundary` is responsible for the main cost.