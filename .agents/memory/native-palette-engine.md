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
`NativePaletteBridge.kt` — androidx.palette MMCQ (maximumColorCount=32, clearFilters) + custom selectBestFive().
Reads artwork directly from ArtworkCacheManager (no bytes transfer over MethodChannel).
Registered in MainActivity.configureFlutterEngine → setupNativePaletteChannel().
Runs on artworkExecutor (bounded 2-thread pool).

## Selection Algorithm (current)
1. Filter chromatic candidates: sat ≥ 0.10, lightness 0.06–0.93
2. Score: 70% popFactor(log-scaled) + 30% vibrancy(sat^0.8) × lightFactor(peak L=0.50) × centerBoost(×1.15) × darkBonus(×1.20 if L<0.25)
3. Harmony triplet from top-12: maximize sum_scores × (1 + 0.5 × harmonyScore)
4. Roles: most saturated = accent; highest pop of rest = primary; remainder = secondary
5. **Neutral-dominance correction (Step 5b):** after triplet, check all swatches (unfiltered) for dominant neutral (S < 0.12, L 0.08–0.92). If neutral.population > primary.population × 2.0 → promote neutral to primary. This prevents near-achromatic album art backgrounds (white, gray) being overridden by small saturated logo accents.
6. Highlight/shadow: hue-coherent candidates from remainder; for neutral primaries (S < 0.12) skip hue-coherence check, derive directly from primary.
7. Fallback: named palette swatches → hardcoded colors

## Dart Cache
LRU 256 entries + debounced disk persist to `artwork/palette_cache_v3.json`.
Cache was at v2; bumped to v3 when neutral-dominance correction was added.

**Why:** Dart palette_generator_plus had two problems: (1) Dart isolate overhead for decode+quantize, (2) naïve selection ignoring hue diversity and vibrance. Native approach eliminates both.

**Why neutral-dominance fix:** saturation filter (S ≥ 0.10) correctly excludes achromatic noise from harmony triplet, but for artwork with white/gray backgrounds + vivid logo (e.g. band photo on white canvas), it discards 80% of pixels, leaving only the logo colour to dominate the BG. The post-triplet neutral check restores the true background mood without breaking the chromatic harmony logic.

**How to apply:** Never re-add palette_generator_plus. Extending selectBestFive() in NativePaletteBridge.kt is the correct extension point. Cache version must be bumped whenever the extraction algorithm changes meaningfully.

## Build dep
`androidx.palette:palette:1.0.0` added to android/app/build.gradle dependencies.
