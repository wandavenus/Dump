---
name: Native Palette Engine
description: androidx.palette MMCQ + custom perceptual selection replaces palette_generator_plus; covers channel name, selection algorithm, fallback chain, and migration notes.
---

## Rule
Use `NativePaletteService` (lib/services/native_palette_service.dart) for all palette extraction.
`PaletteExtractor` and `palette_generator_plus` have been fully removed.

## Channel
`dev.wndavenz.music/native_palette` — method `extractPalette(songId: Int)` → `List<Int>` (5 ARGB values)

## Native side
`NativePaletteBridge.kt` — androidx.palette MMCQ (maximumColorCount=96, clearFilters) + custom selectBestFive().
Reads artwork directly from ArtworkCacheManager (no bytes transfer over MethodChannel).
Registered in MainActivity.configureFlutterEngine → setupNativePaletteChannel().
Runs on artworkExecutor (bounded 2-thread pool).

## Selection Algorithm (current)
1. Filter chromatic candidates: sat ≥ 0.10, lightness 0.06–0.93
2. Score: `(0.90 × population + 0.10 × sat^0.8) × lightness × darkBonus`; there is no spatial/center weighting. Decode uses ARGB_8888.
3. Merge perceptually similar swatches with OKLab before role selection.
4. Coverage-driven roles: primary = largest family; secondary/accent = remaining families ranked by population plus perceptual distance from already-selected roles.
5. **Neutral-dominance correction:** after chromatic selection, a truly dominant neutral (S < 0.12, full lightness range) can replace primary. This includes near-black and near-white artwork backgrounds.
6. Highlight/shadow: use distinct remaining artwork clusters where possible, otherwise derive from primary.
7. Fallback: named palette swatches → hardcoded colors

## Dart Cache
LRU 256 entries + debounced disk persist to the versioned palette cache file.
The native cache version is currently v8. It is read by Dart through
`getCacheVersion` and used in the persisted filename; v8 preserves
one/two-family palettes.

**Historical rationale:** The legacy Dart `palette_generator_plus` path had
decode/quantize isolate overhead and naïve role selection. The active native
approach eliminates that old path and uses population-led perceptual selection.

**Why neutral-dominance fix:** the chromatic filter (S ≥ 0.10) excludes
achromatic candidates from role selection, but neutral backgrounds can be the
true visual anchor. The post-selection neutral check restores a neutral primary
when its population exceeds twice the selected chromatic family's merged
population, including near-black and near-white artwork.

**Why coverage-driven roles:** selecting only by hue harmony can choose several
related blue clusters and discard a real warm family such as skin or beige.
Role selection therefore preserves perceptually distinct, sufficiently
populated families using coverage plus perceptual distance; legacy harmony
helpers remain diagnostic-only.

**How to apply:** Never re-add palette_generator_plus. Extending selectBestFive() in NativePaletteBridge.kt is the correct extension point. Cache version must be bumped whenever the extraction algorithm changes meaningfully.

## Bridge lifecycle and cache-version contract

`NativePaletteBridge` owns request completion state and must be disposed before
the Activity shuts down its shared artwork executor. `NativePaletteService` asks
the bridge for `CACHE_VERSION` during warm-up and uses that value for persisted
cache naming.

**Why:** A queued native request can otherwise lose its MethodChannel callback
during engine teardown, and a native algorithm revision can otherwise keep
serving stale Dart cache entries.

**How to apply:** Any new asynchronous bridge method must register a pending
request, complete exactly once, and participate in `dispose()`. Any palette
selection change must bump the native cache version; do not hardcode a second
independent version in Dart except as an older-engine fallback.

v8 keeps a valid second family as accent when clustering produces only two
families, derives a related secondary tone from primary, and uses the
highest-scoring cluster as primary unless dominant-neutral correction applies.

## Important failure mode

The OKLab merge threshold and greedy “any member” matching can collapse an artwork
into fewer than three clusters. If role selection treats that as a hard fallback,
the named Palette swatches can mask the new coverage algorithm and often return
related blue tones again.

**Why:** A palette may contain only two perceptually meaningful families (for
example, dark blue plus warm beige), but that is still a valid result for
primary/secondary/accent. Falling back loses the warm family entirely.

**How to apply:** Do not replace a valid two-family extraction with generic named
swatches. Preserve the available distinct families and derive only the missing
role; test the `< 3 clusters` path explicitly.

**Failure handling:** Native queue rejection and extraction exceptions are
returned as MethodChannel errors. Dart must not persist the fallback for these
transient failures; a normal successful extraction that legitimately has no
usable artwork may still return and cache the fallback.

## Queue saturation protection

Native requests for the same `songId` share one in-flight extraction job.
The bridge keeps the artwork executor bounded at two threads and emits sampled
debug metrics for extraction count, coalesced requests, queue rejections, and
average duration. Dart uses a longer bounded retry delay after `palette_busy`.

**Why:** Artwork cache work and palette extraction share the target device's
small artwork pool. Repeating decode/MMCQ for identical requests amplifies
bursts and makes queue saturation more likely.

**How to apply:** Preserve per-song coalescing and exactly-once completion when
adding bridge methods. Do not increase worker count without measurements from
the target Xiaomi device.

## Build dep
`androidx.palette:palette:1.0.0` added to android/app/build.gradle dependencies.
